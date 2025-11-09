<p align="center">
  <a>
    <img src="imgs/Logo.png" alt="Logo">
  </a>

***TRABAJO PRACTICO 2***

**Titulo:** UART Parametrizable para Control de ALU

**Asignatura:** Arquitectura de Computadoras

**Integrantes:**
   - Ignacio Ledesma
   - Ivan Zuñiga

---------------

## Enunciado

Desarrollar una UART (Universal Asynchronous Receiver-Transmitter) parametrizable en SystemVerilog para controlar la ALU desarrollada en el trabajo práctico anterior. La UART debe implementar comunicación serie full-duplex con parámetros configurables, incluyendo generador de baudrate, módulo transmisor y receptor.

Este informe se centra en el **fundamento teórico y diseño del generador de baudrate**, que constituye la base temporal para toda comunicación UART confiable.

### Requerimientos

1. **Generador de Baudrate:**
    - Implementar un divisor de frecuencia que genere señales de temporización para UART
    - Utilizar la frecuencia de reloj de 12 MHz de la Cmod A7-35T
    - Generar baudrate de 9600 bps con justificación técnica de la elección
    - Implementar oversampling con factor justificado teóricamente

2. **Módulo Transmisor UART (TX):**
    - Implementar máquina de estados para transmisión serie
    - Soportar formato configurable: 8 bits de datos (parametrizable)
    - Incluir bit de paridad (parametrizable: par, impar, ninguna)
    - Configurar 1 stop bit (parametrizable)

3. **Módulo Receptor UART (RX):**
    - Implementar máquina de estados para recepción serie
    - Detectar automáticamente el bit de start
    - Muestrear datos en el centro del bit usando oversampling
    - Verificar paridad y detectar errores de trama

4. **Integración con ALU:**
    - Interfaz de comandos para controlar la ALU del TP anterior
    - Protocolo de comunicación para envío de operandos y opcodes
    - Lectura de resultados y flags de la ALU vía UART

5. **Parametrización:**
    - Ancho de datos configurable (por defecto 8 bits)
    - Tipo de paridad configurable
    - Número de stop bits configurable
    - Baudrate configurable mediante parámetros

**Nota:** Este informe presenta el análisis teórico del generador de baudrate, que constituye el componente fundamental del sistema UART completo.

---

## Marco Teórico

### Comunicación UART

La comunicación UART (Universal Asynchronous Receiver-Transmitter) es un protocolo de comunicación serie asíncrona ampliamente utilizado en sistemas embebidos. A diferencia de los protocolos síncronos, UART no requiere una línea de reloj compartida, sino que depende de que ambos extremos de la comunicación operen a la misma velocidad de transmisión (baudrate).

### Baudrate y Temporización

El baudrate define la velocidad de transmisión en bits por segundo (bps). Para una comunicación exitosa, ambos dispositivos deben estar sincronizados temporalmente:

```
Tiempo por bit = 1 / Baudrate
Para 9600 bps: Tiempo por bit = 1/9600 ≈ 104.17 μs
```

### Oversampling en Sistemas UART

El oversampling es una técnica que consiste en muestrear la señal de entrada múltiples veces durante cada período de bit. Esto proporciona varios beneficios:

- **Tolerancia a variaciones de frecuencia**: Compensa pequeñas diferencias entre los relojes del transmisor y receptor
- **Inmunidad al ruido**: Permite detectar y filtrar transiciones espurias
- **Detección de errores de trama**: Facilita la identificación de bits de start y stop incorrectos
- **Sincronización robusta**: Permite encontrar el centro óptimo de cada bit para el muestreo

---

## Desarrollo

### Especificaciones del Sistema

#### Plataforma de Desarrollo

- **FPGA:** Xilinx Artix-7 (XC7A35T-1CPG236C) en placa Cmod A7-35T
- **Frecuencia de reloj:** 12 MHz (oscilador integrado)
- **Herramientas:** Vivado, SystemVerilog
- **Protocolo:** UART parametrizable (8 bits de datos, paridad, 1 stop bit)

#### Justificación del Baudrate de 9600 bps

La selección de 9600 bps como velocidad de transmisión se basa en múltiples consideraciones técnicas y prácticas:

**1. Compatibilidad Universal**
- 9600 bps es uno de los baudrates estándar más ampliamente soportados
- Garantiza compatibilidad con la mayoría de dispositivos y software de terminal
- Es el baudrate por defecto en muchos microcontroladores y sistemas embebidos

**2. Precisión con Reloj de 12 MHz**
```
Factor de división = 12,000,000 Hz ÷ 9600 bps = 1250
Error de cuantización = 0% (división exacta)
```
Esta división exacta elimina completamente el error de cuantización, proporcionando una precisión perfecta en la temporización.

**3. Robustez para Conexiones Largas**
- Velocidades menores (como 9600 bps) son más tolerantes a:
  - Capacitancia parasitaria en cables largos
  - Interferencia electromagnética
  - Variaciones en las características de los drivers de línea
  - Diferencias en los niveles de voltaje entre dispositivos

**4. Comparación con Otros Baudrates Comunes**

| Baudrate | Factor División | Error | Observaciones |
|----------|----------------|-------|---------------|
| 4800 bps | 2500 | 0% | Muy lento para aplicaciones interactivas |
| 9600 bps | 1250 | 0% | **ÓPTIMO: División exacta, velocidad adecuada** |
| 19200 bps | 625 | 0% | Rápido, pero menos tolerante a ruido |
| 38400 bps | 312.5 | ~0.16% | Requiere aproximación, introduce error |
| 115200 bps | ~104.17 | ~0.16% | Muy rápido, sensible a condiciones de línea |

**5. Consideraciones de Potencia**
- Baudrates menores resultan en menor actividad de conmutación
- Reduce el consumo de potencia en sistemas alimentados por batería
- Disminuye la generación de EMI (interferencia electromagnética)

#### Justificación del Factor de Oversampling 16x

La elección del factor de oversampling de 16x se fundamenta en principios teóricos de procesamiento de señales y estándares de la industria:

**1. Fundamento Teórico - Teorema de Nyquist**
```
Frecuencia de muestreo mínima = 2 × frecuencia máxima de la señal
Para baudrate de 9600 bps: fmin = 2 × 9600 = 19.2 kHz

Con oversampling 16x: fsampling = 16 × 9600 = 153.6 kHz
Margen de seguridad = 153.6 / 19.2 = 8x sobre el mínimo teórico
```

**2. Estándar de la Industria**
- 16x es el factor de oversampling más común en UARTs comerciales

**3. Análisis de Tolerancia al Error de Frecuencia**

Con oversampling de 16x, el sistema puede tolerar errores de frecuencia según:
```
Error máximo tolerable ≈ ±3.125% (para 10 bits transmitidos)
Error por muestra = Error total / (16 muestras × 10 bits) = ±0.0195%
```

**4. Comparación de Factores de Oversampling**

| Factor | Frecuencia Muestreo | Tolerancia Error | Complejidad | Recursos |
|--------|-------------------|------------------|-------------|----------|
| 8x | 76.8 kHz | ±6.25% | Baja | Mínimos |
| **16x** | **153.6 kHz** | **±3.125%** | **Media** | **Moderados** |
| 32x | 307.2 kHz | ±1.56% | Alta | Altos |
| 64x | 614.4 kHz | ±0.78% | Muy Alta | Muy Altos |

**5. Ventajas del Factor 16x**
- **Detección precisa del centro de bit**: 8 muestras antes y después del centro
- **Filtrado de ruido efectivo**: Múltiples muestras por bit para decisión por mayoría
- **Sincronización robusta**: Suficientes muestras para detectar flancos con precisión
- **Equilibrio recursos/rendimiento**: Óptimo para FPGAs

---
