/**
 * @file main.cpp
 * @brief Driver de comunicación entre Raspberry Pi Pico 2 y FPGA ALU en placa Cmod A7
 * @author Tu nombre aquí
 * @version 1.0
 * @date 2025
 * 
 * @details Este programa implementa un controlador de bus para comunicar un Raspberry Pi Pico 2
 * con una ALU implementada en FPGA en una placa Cmod A7. La comunicación se realiza a través
 * de un protocolo de comandos simple sobre UART.
 * 
 * @section protocolo Protocolo de Comandos
 * El protocolo soporta los siguientes comandos (disponibles en UART Serial1 y USB Serial):
 * - A <valor>  : Carga operando A (acepta decimal/hex, ej. A 42 o A 0x2A)
 * - B <valor>  : Carga operando B
 * - S <valor>  : Carga opcode/selección (máscara de 5 bits)
 * - W <valor>  : Controla bus de datos sin capturar (para inspección)
 * - R          : Pulso de reset síncrono en el FPGA
 * - P          : Imprime pines de estado (Cout/Zero/Overflow)
 * - H          : Ayuda/resumen
 * 
 * @section funcionamiento Funcionamiento
 * Cada carga genera un pulso alto activo lo suficientemente largo para cruzar el dominio 
 * de reloj del FPGA de 12 MHz. Los resultados son visibles en placa vía LEDs; los bits 
 * de estado también pueden cablearse de vuelta al Pico y consultarse con 'P'.
 * 
 * @section conexiones Conexiones GPIO
 * - GP2-GP9: Bus de datos de 8 bits (data_in[0:7])
 * - GP10: Señal de carga operando A (load_a)
 * - GP11: Señal de carga operando B (load_b)
 * - GP12: Señal de carga selector de operación (load_sel)
 * - GP13: Señal de reset (rst, activo alto)
 * - GP14: Carry out (Cout)
 * - GP15: Flag Zero
 * - GP16: Flag Overflow
 * - GP17-GP22, GP26-GP27: Bus de resultado de 8 bits
 */

#include <Arduino.h>
#include <ctype.h>

/**
 * @name Configuración de velocidades UART
 * @{
 */
static constexpr unsigned long BAUD_USB  = 115200; ///< Velocidad USB CDC
static constexpr unsigned long BAUD_UART = 115200; ///< Velocidad UART TTL en Serial1
/** @} */

/**
 * @name Mapeo GPIO
 * @brief Mapeo de números GP del Pico a pines de header PIO de Cmod A7
 * @{
 */
static constexpr uint8_t PIN_DATA[8]   = { 2, 3, 4, 5, 6, 7, 8, 9 }; ///< Bus de datos 8 bits -> PIO1..PIO8 (data_in[0:7])
static constexpr uint8_t PIN_LOAD_A    = 10;                          ///< Señal de carga operando A -> PIO9 (load_a)
static constexpr uint8_t PIN_LOAD_B    = 11;                          ///< Señal de carga operando B -> PIO10 (load_b)
static constexpr uint8_t PIN_LOAD_SEL  = 12;                          ///< Señal de carga selector -> PIO11 (load_sel)
static constexpr uint8_t PIN_RST       = 13;                          ///< Señal de reset -> PIO12 (rst, activo alto)
static constexpr uint8_t PIN_COUT      = 14;                          ///< Carry out -> PIO13 (Cout)
static constexpr uint8_t PIN_ZERO      = 15;                          ///< Flag Zero -> PIO14 (Zero)
static constexpr uint8_t PIN_OVERFLOW  = 16;                          ///< Flag Overflow -> PIO40 (Overflow)
static constexpr uint8_t PIN_RESULT[8] = { 17, 18, 19, 20, 21, 22, 26, 27 }; ///< Bus de resultado 8 bits -> PIO41..PIO48
/** @} */

/**
 * @name Constantes de temporización
 * @{
 */
static constexpr unsigned LOAD_PULSE_US = 20; ///< Duración pulso de carga en microsegundos (>1 reloj FPGA a 12 MHz)
static constexpr unsigned RESET_MS      = 2;  ///< Duración reset síncrono en milisegundos
static constexpr unsigned HEARTBEAT_MS  = 1000; ///< Período mensaje de vida en milisegundos
/** @} */

/**
 * @struct CommandInput
 * @brief Estructura para manejar entrada de comandos por puerto serial
 */
struct CommandInput {
  Stream* port;      ///< Puntero al puerto serial (Serial o Serial1)
  char buffer[48];   ///< Buffer para almacenar comando en proceso
  size_t len;        ///< Longitud actual del comando en el buffer
};

/**
 * @brief Array de estructuras para manejar múltiples puertos seriales
 * @details Permite procesar comandos tanto del USB (Serial) como del UART (Serial1)
 */
CommandInput inputs[] = {
  { &Serial,  {0}, 0 },  ///< Puerto USB CDC
  { &Serial1, {0}, 0 }   ///< Puerto UART TTL
};

// -----------------------------------------------------------------------------
// Funciones Auxiliares
// -----------------------------------------------------------------------------
/**
 * @brief Limpia un buffer de caracteres
 * @tparam N Tamaño del buffer
 * @param buf Referencia al buffer a limpiar
 */
template <size_t N>
void clear_buffer(char (&buf)[N]) {
  memset(buf, 0, N);
}

/**
 * @brief Escribe una línea con mensaje de Flash al puerto serial
 * @param port Referencia al puerto serial
 * @param msg Puntero al mensaje en memoria Flash
 */
void write_line(Stream& port, const __FlashStringHelper* msg) {
  port.println(msg);
}

/**
 * @brief Escribe una línea con mensaje desde RAM al puerto serial
 * @param port Referencia al puerto serial
 * @param msg Puntero al mensaje en RAM
 */
void write_line(Stream& port, const char* msg) {
  port.println(msg);
}

/**
 * @brief Establece el valor del bus de datos de 8 bits
 * @param value Valor de 8 bits a establecer en el bus
 * @details Configura los pines GPIO correspondientes al bus de datos
 * con los bits del valor proporcionado (LSB en PIN_DATA[0])
 */
void set_data_bus(uint8_t value) {
  for (uint8_t i = 0; i < 8; ++i) {
    digitalWrite(PIN_DATA[i], (value >> i) & 0x01);
  }
}

/**
 * @brief Genera un pulso alto en un pin específico
 * @param pin Número del pin GPIO
 * @param usec Duración del pulso en microsegundos
 * @details Establece el pin en HIGH por la duración especificada,
 * luego lo regresa a LOW con una pausa adicional
 */
void pulse_high(uint8_t pin, unsigned usec) {
  digitalWrite(pin, HIGH);
  delayMicroseconds(usec);
  digitalWrite(pin, LOW);
  delayMicroseconds(usec);
}

/**
 * @brief Genera un pulso de reset síncrono para el FPGA
 * @details Establece la señal de reset en HIGH por RESET_MS milisegundos,
 * luego la regresa a LOW. Esto reinicia el estado del FPGA.
 */
void reset_fpga() {
  digitalWrite(PIN_RST, HIGH);
  delay(RESET_MS);
  digitalWrite(PIN_RST, LOW);
  delay(RESET_MS);
}

/**
 * @brief Lee los flags de estado del FPGA y los combina en una máscara
 * @return Máscara de 8 bits con los flags de estado (Cout, Zero, Overflow)
 * @details Lee los pines de entrada correspondientes a los flags de estado
 * y los empaqueta en un byte: bit 0 = Cout, bit 1 = Zero, bit 2 = Overflow
 */
uint8_t read_status_mask() {
  uint8_t mask = 0;
  mask |= (digitalRead(PIN_COUT)     & 0x1) << 0;
  mask |= (digitalRead(PIN_ZERO)     & 0x1) << 1;
  mask |= (digitalRead(PIN_OVERFLOW) & 0x1) << 2;
  return mask;
}

/**
 * @brief Lee el bus de resultado de 8 bits desde los pines GPIO
 * @return Valor de 8 bits leído del bus de resultado
 * @details Lee los 8 pines correspondientes al bus de resultado
 * y los combina en un byte (LSB en PIN_RESULT[0])
 */
uint8_t read_result_bus() {
  uint8_t value = 0;
  for (uint8_t i = 0; i < 8; ++i) {
    value |= (digitalRead(PIN_RESULT[i]) & 0x1) << i;
  }
  return value;
}

/**
 * @brief Imprime el estado actual del resultado y flags en el puerto serial
 * @param port Referencia al puerto serial donde imprimir el estado
 * @details Lee el bus de resultado y los flags de estado, luego los
 * formatea e imprime en el puerto especificado en formato legible
 */
void print_snapshot(Stream& port) {
  uint8_t result = read_result_bus();
  uint8_t mask = read_status_mask();
  port.print(F("Result=0x"));
  if (result < 0x10) {
    port.print('0');
  }
  port.print(result, HEX);
  port.print(F(" Cout="));
  port.print((mask >> 0) & 0x1);
  port.print(F(" Zero="));
  port.print((mask >> 1) & 0x1);
  port.print(F(" Overflow="));
  port.println((mask >> 2) & 0x1);
}

/**
 * @brief Parsea una cadena de texto a un valor de 8 bits
 * @param token Cadena de texto a parsear
 * @param out Referencia donde almacenar el resultado parseado
 * @return true si el parseo fue exitoso, false en caso contrario
 * @details Soporta valores en decimal y hexadecimal (prefijo 0x).
 * Valida que el valor esté en el rango 0-255.
 */
bool parse_byte(const char* token, uint8_t& out) {
  if (token == nullptr) {
    return false;
  }

  while (*token == ' ' || *token == '\t') {
    ++token;
  }

  if (*token == '\0') {
    return false;
  }

  char* end = nullptr;
  long value = strtol(token, &end, 0); 
  if (end == token || value < 0 || value > 255) {
    return false;
  }

  out = static_cast<uint8_t>(value & 0xFF);
  return true;
}

/**
 * @brief Muestra el texto de ayuda con la lista de comandos disponibles
 * @param port Referencia al puerto serial donde mostrar la ayuda
 * @details Imprime la lista completa de comandos soportados por el protocolo
 * incluyendo descripción y formato de cada comando
 */
void service_help(Stream& port) {
  // Muestra el texto de ayuda con la lista de comandos disponibles
  write_line(port, F("Comandos:"));
  write_line(port, F("  A <val>  Carga operando A"));
  write_line(port, F("  B <val>  Carga operando B"));
  write_line(port, F("  S <val>  Carga opcode (máscara de 5 bits)"));
  write_line(port, F("  W <val>  Controla bus de datos sin capturar"));
  write_line(port, F("  R        Pulso de reset síncrono"));
  write_line(port, F("  P        Imprime resultado + pines de estado"));
  write_line(port, F("  H        Esta ayuda"));
  write_line(port, F("Los valores aceptan decimal o hex prefijado con 0x."));
}

/**
 * @brief Procesa y ejecuta un comando recibido por el puerto serial
 * @param line Cadena de texto con el comando a procesar
 * @param reply Referencia al puerto serial donde enviar la respuesta
 * @details Parsea el comando, valida parámetros y ejecuta la acción correspondiente.
 * Soporta los comandos: A (carga operando A), B (carga operando B), S (carga opcode),
 * W (escritura directa al bus), R (reset), P (imprimir estado), H (ayuda)
 */
void handle_command(const char* line, Stream& reply) {
  if (line == nullptr || *line == '\0') {
    return;
  }

  char cmd = toupper(static_cast<unsigned char>(line[0]));
  const char* arg = line + 1;
  while (*arg == ' ' || *arg == '\t') {
    ++arg;
  }

  uint8_t value = 0;

  switch (cmd) {
    case 'A':
      if (!parse_byte(arg, value)) {
        write_line(reply, F("ERR: valor esperado para A"));
        break;
      }
      set_data_bus(value);
      pulse_high(PIN_LOAD_A, LOAD_PULSE_US);
      reply.print(F("Cargado A = 0x"));
      reply.println(value, HEX);
      print_snapshot(reply);
      break;

    case 'B':
      if (!parse_byte(arg, value)) {
        write_line(reply, F("ERR: valor esperado para B"));
        break;
      }
      set_data_bus(value);
      pulse_high(PIN_LOAD_B, LOAD_PULSE_US);
      reply.print(F("Cargado B = 0x"));
      reply.println(value, HEX);
      print_snapshot(reply);
      break;

    case 'S':
      if (!parse_byte(arg, value)) {
        write_line(reply, F("ERR: valor esperado para opcode"));
        break;
      }
      value &= 0x3F; 
      set_data_bus(value);
      pulse_high(PIN_LOAD_SEL, LOAD_PULSE_US);
      reply.print(F("Cargado opcode = 0x"));
      reply.println(value, HEX);
      print_snapshot(reply);
      break;

    case 'W':
      if (!parse_byte(arg, value)) {
        write_line(reply, F("ERR: valor esperado para escritura en bus"));
        break;
      }
      set_data_bus(value);
      reply.print(F("Bus establecido a 0x"));
      reply.println(value, HEX);
      break;

    case 'R':
      reset_fpga();
      write_line(reply, F("Pulso de reset enviado."));
      print_snapshot(reply);
      break;

    case 'P':
      print_snapshot(reply);
      break;

    case 'H':
      service_help(reply);
      break;

    default:
      write_line(reply, F("Comando desconocido. Usa 'H' para ayuda."));
      break;
  }

  reply.println();
}

/**
 * @brief Procesa la entrada serial de un puerto y maneja comandos completos
 * @param input Referencia a la estructura CommandInput que contiene el puerto y buffer
 * @details Lee caracteres del puerto serial, los acumula en un buffer hasta recibir
 * un carácter de nueva línea, entonces procesa el comando completo. Ignora retornos
 * de carro y maneja desbordamiento del buffer.
 */
void service_input(CommandInput& input) {
  Stream& port = *input.port;

  while (port.available() > 0) {
    char ch = static_cast<char>(port.read());
    if (ch == '\r') {
      continue;
    }

    if (ch == '\n') {
      input.buffer[input.len] = '\0';
      handle_command(input.buffer, port);
      input.len = 0;
      clear_buffer(input.buffer);
      port.print(F("> "));
      continue;
    }

    if (input.len < sizeof(input.buffer) - 1) {
      input.buffer[input.len++] = ch;
    }
  }
}

// -----------------------------------------------------------------------------
// Configuración y Bucle Principal de Arduino
// -----------------------------------------------------------------------------

/**
 * @brief Función de configuración inicial de Arduino
 * @details Configura todos los pines GPIO como entrada o salida según corresponda:
 * - Configura pines del bus de datos como salidas en estado LOW
 * - Configura pines de control (load_a, load_b, load_sel, rst) como salidas en LOW
 * - Configura pines de estado (cout, zero, overflow) como entradas con pull-down
 * - Configura pines del bus de resultado como entradas con pull-down
 * - Inicializa comunicaciones seriales (USB y UART)
 * - Muestra mensaje de bienvenida y ayuda
 * - Ejecuta reset inicial del FPGA
 */
void setup() {
  for (uint8_t pin : PIN_DATA) {
    pinMode(pin, OUTPUT);
    digitalWrite(pin, LOW);
  }

  pinMode(PIN_LOAD_A, OUTPUT);
  pinMode(PIN_LOAD_B, OUTPUT);
  pinMode(PIN_LOAD_SEL, OUTPUT);
  pinMode(PIN_RST, OUTPUT);

  digitalWrite(PIN_LOAD_A, LOW);
  digitalWrite(PIN_LOAD_B, LOW);
  digitalWrite(PIN_LOAD_SEL, LOW);
  digitalWrite(PIN_RST, LOW);

  pinMode(PIN_COUT, INPUT_PULLDOWN);
  pinMode(PIN_ZERO, INPUT_PULLDOWN);
  pinMode(PIN_OVERFLOW, INPUT_PULLDOWN);

  for (uint8_t pin : PIN_RESULT) {
    pinMode(pin, INPUT_PULLDOWN);
  }

  Serial.begin(BAUD_USB);
  Serial1.begin(BAUD_UART);

  delay(200);

  write_line(Serial, F("Driver Pico -> ALU Cmod listo."));
  service_help(Serial);
  Serial.print(F("> "));

  Serial1.println(F("Driver Pico -> ALU Cmod listo."));
  Serial1.print(F("> "));

  reset_fpga();
}

/**
 * @brief Bucle principal de Arduino
 * @details Ejecuta continuamente el procesamiento de comandos desde ambos
 * puertos seriales (USB y UART). No utiliza delays para mantener la respuesta
 * rápida a los comandos entrantes.
 */
void loop() {
  for (auto& input : inputs) {
    service_input(input);
  }
}
