```plantuml
@startuml
title System Architecture
top to bottom direction
skinparam backgroundColor #0f172a

skinparam componentStyle rectangle
skinparam defaultFontName Consolas

' ---- Colors tuned for dark UI ----
skinparam rectangle {
  BackgroundColor #1f2937
  BorderColor #94a3b8
  FontColor #e5e7eb
  RoundCorner 14
  FontSize 13
}
skinparam package {
  BackgroundColor #111827
  BorderColor #93c5fd
  FontColor #e5e7eb
  FontStyle bold
  RoundCorner 16
  FontSize 14
}
skinparam note {
  BackgroundColor #0b2538
  BorderColor #38bdf8
  FontColor #e0f2fe
  Shadowing 0
}
skinparam arrow {
  Color #f8fafc
  FontColor #f8fafc
  Thickness 1.4
  FontSize 12
}

' ==== UART RECEPTION ====
package "UART Reception" {
  [UART RX\n«uart»] as UART_RX
  rectangle "UART Packet Decoder\n«decoder»\n\nInputs:\n  • rx_byte(8), rx_valid\nOutputs:\n  • alu_data(8)\n  • load_a/load_b/load_sel pulses\n  • exec_pulse\nNotas:\n  • framing [STX][CMD][DATA][ETX]" as DEC #0f2332

  UART_RX -down-> DEC : uart_read_byte()
}

' ==== CORE ====
package "Core Application Logic" {
  rectangle "Main Control Block\n«fsm»\n\nInputs:\n  • alu_data(8)\n  • load_a/load_b/load_sel\n  • exec_pulse\nOutputs:\n  • tx_data(8), tx_write_en\nContracts:\n  • controla alu_top\n  • fifo_write_tx()" as CORE #0f2332
}

' ==== UART TRANSMISSION ====
package "UART Transmission" {
  [TX FIFO\n«fifo»] as FIFO_TX
  [UART TX\n«uart»] as UART_TX

  FIFO_TX -down-> UART_TX : uart_write_byte()
}

' ==== CONNECTIONS (VERTICAL PIPELINE) ====
DEC -down-> CORE : load/data hacia ALU
CORE -down-> FIFO_TX : fifo_write_tx()

' Notes kept minimal so you can explain in Markdown below
note right of DEC
  Internal behavior: UART Packet Decoder – FSM
end note
note right of CORE
  Internal behavior: Main Control FSM – ALU UART Interface
end note
@enduml
