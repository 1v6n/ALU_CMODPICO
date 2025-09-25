#include <Arduino.h>
#include <ctype.h>

// -----------------------------------------------------------------------------
// Driver de bus ALU Cmod A7 <-> Pico 2
// -----------------------------------------------------------------------------
// Protocolo de comandos (sobre UART Serial1 y USB Serial):
//   A <valor>  : carga operando A  (valor aceptado en decimal/hex, ej. A 42 o A 0x2A)
//   B <valor>  : carga operando B
//   S <valor>  : carga opcode/selección (máscara de 5 bits)
//   W <valor>  : controla bus de datos sin capturar (para inspección)
//   R          : pulso de reset síncrono en el FPGA
//   P          : imprime pines de estado (Cout/Zero/Overflow)
//   H          : ayuda/resumen
// Cada carga genera un pulso alto activo lo suficientemente largo para cruzar el dominio de reloj del FPGA de 12 MHz.
// Los resultados son visibles en placa vía LEDs; los bits de estado también pueden cablearse de vuelta al Pico y consultarse con 'P'.

// Velocidades UART
static constexpr unsigned long BAUD_USB  = 115200; // USB CDC
static constexpr unsigned long BAUD_UART = 115200; // UART TTL en Serial1

// Mapeo GPIO (números GP del Pico -> pines de header PIO de Cmod A7)
static constexpr uint8_t PIN_DATA[8]   = { 2, 3, 4, 5, 6, 7, 8, 9 }; // -> PIO1..PIO8 (data_in[0:7])
static constexpr uint8_t PIN_LOAD_A    = 10;                          // -> PIO9 (load_a)
static constexpr uint8_t PIN_LOAD_B    = 11;                          // -> PIO10 (load_b)
static constexpr uint8_t PIN_LOAD_SEL  = 12;                          // -> PIO11 (load_sel)
static constexpr uint8_t PIN_RST       = 13;                          // -> PIO12 (rst, activo alto)
static constexpr uint8_t PIN_COUT      = 14;                          // -> PIO13 (Cout)
static constexpr uint8_t PIN_ZERO      = 15;                          // -> PIO14 (Zero)
static constexpr uint8_t PIN_OVERFLOW  = 16;                          // -> PIO40 (Overflow)
static constexpr uint8_t PIN_RESULT[8] = { 17, 18, 19, 20, 21, 22, 26, 27 }; // -> PIO41..PIO48 sentido de resultado

static constexpr unsigned LOAD_PULSE_US = 20; // >1 reloj FPGA (12 MHz)
static constexpr unsigned RESET_MS      = 2;  // Reset síncrono suave
static constexpr unsigned HEARTBEAT_MS  = 1000; // Mensaje de vida periódico

struct CommandInput {
  Stream* port;
  char buffer[48];
  size_t len;
};

CommandInput inputs[] = {
  { &Serial,  {0}, 0 },
  { &Serial1, {0}, 0 }
};

// -----------------------------------------------------------------------------
// Funciones Auxiliares
// -----------------------------------------------------------------------------
template <size_t N>
void clear_buffer(char (&buf)[N]) {
  memset(buf, 0, N);
}

void write_line(Stream& port, const __FlashStringHelper* msg) {
  port.println(msg);
}

void write_line(Stream& port, const char* msg) {
  port.println(msg);
}

void set_data_bus(uint8_t value) {
  // Establece el bus de datos de 8 bits en los pines GPIO correspondientes
  for (uint8_t i = 0; i < 8; ++i) {
    digitalWrite(PIN_DATA[i], (value >> i) & 0x01);
  }
}

void pulse_high(uint8_t pin, unsigned usec) {
  // Genera un pulso alto en el pin por la duración especificada
  digitalWrite(pin, HIGH);
  delayMicroseconds(usec);
  digitalWrite(pin, LOW);
  delayMicroseconds(usec);
}

void reset_fpga() {
  // Genera un pulso de reset síncrono en el FPGA
  digitalWrite(PIN_RST, HIGH);
  delay(RESET_MS);
  digitalWrite(PIN_RST, LOW);
  delay(RESET_MS);
}

uint8_t read_status_mask() {
  // Lee los flags de estado del FPGA y los combina en una máscara
  uint8_t mask = 0;
  mask |= (digitalRead(PIN_COUT)     & 0x1) << 0;
  mask |= (digitalRead(PIN_ZERO)     & 0x1) << 1;
  mask |= (digitalRead(PIN_OVERFLOW) & 0x1) << 2;
  return mask;
}

uint8_t read_result_bus() {
  // Lee el bus de resultados de 8 bits desde los pines GPIO
  uint8_t value = 0;
  for (uint8_t i = 0; i < 8; ++i) {
    value |= (digitalRead(PIN_RESULT[i]) & 0x1) << i;
  }
  return value;
}

void print_snapshot(Stream& port) {
  // Imprime el resultado actual y flags de estado en el puerto serial
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

bool parse_byte(const char* token, uint8_t& out) {
  // Parsea un token de cadena a un byte de 8 bits, detectando base automáticamente (decimal, hex 0x)
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
  long value = strtol(token, &end, 0); // Auto-detecta base (0x.., decimal)
  if (end == token || value < 0 || value > 255) {
    return false;
  }

  out = static_cast<uint8_t>(value & 0xFF);
  return true;
}

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

void handle_command(const char* line, Stream& reply) {
  // Procesa un comando recibido, ejecuta la acción correspondiente y responde
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
      value &= 0x1F; // OPCODE_WIDTH = 5
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

void service_input(CommandInput& input) {
  // Procesa entrada serial del puerto, parsea comandos y los ejecuta
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
void setup() {
  // Configura salidas del bus
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

void loop() {
  // Bucle principal: atiende entradas de ambos puertos seriales
  for (auto& input : inputs) {
    service_input(input);
  }
}
