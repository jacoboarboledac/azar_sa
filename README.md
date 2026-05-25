# Lotería Distribuida en Elixir (Azar S.A.)

Sistema transaccional y distribuido para la gestión, venta y ejecución de sorteos de lotería, construido con Elixir bajo una arquitectura de proyecto paraguas (Umbrella Project).

##Arquitectura del Sistema

El sistema se divide en tres aplicaciones principales que pueden ejecutarse en computadoras distintas comunicándose a través de la red:

* **Servidor Central:** Actúa como el enrutador y base de datos. Gestiona la persistencia en archivos JSON, mantiene la bitácora de operaciones y levanta procesos dinámicos (GenServer) para cada sorteo activo.
* **Administrador:** Interfaz de control para crear sorteos, gestionar premios y disparar la ejecución de las fechas del sistema.
* **Jugador:** Cliente interactivo para que los usuarios se registren, consulten la cartelera y compren billetes o fracciones.
1. **Inicia el Servidor Central (PC 1)**
Averigua tu IP local (ej. `192.168.1.50`) y levanta el nodo usando una cookie de seguridad:
iex --name nodo_servidor@192.168.1.50 --cookie loteria_secreta -S mix

2. **Inicia el Administrador o Jugador (PC 2)**
En otra computadora (ej. IP `192.168.1.60`), levanta el cliente con la misma cookie:
`iex --name nodo_jugador@192.168.1.60 --cookie loteria_secreta -S mix`

##Ejemplos de Uso

**Conexión inicial (Desde Admin o Jugador):**
Apunta el cliente a la IP del servidor central:
`Jugador.conectar("192.168.1.50")`

**Flujo del Administrador:**
`Admin.crear_sorteo("Navideño", "2026-12-24", 100, 5, 50000)`
`Admin.agregar_premio("Navideño", "Premio Mayor", 1000000)`

**Flujo del Jugador:**
`Jugador.registrar("Jacobo", "12345678", "clave123", "0000-0000")`
`Jugador.consultar_sorteos()`
`Jugador.comprar_billete("12345678", "clave123", "Navideño", 15, 2)`

**Ejecución del Sorteo (Admin):**
`Admin.actualizar_fecha("2026-12-24")`
graph TD
    %% Definición de Nodos y Estilos
    classDef cliente fill:#d4edda,stroke:#28a745,stroke-width:2px;
    classDef servidor fill:#cce5ff,stroke:#007bff,stroke-width:2px;
    classDef proceso fill:#fff3cd,stroke:#ffc107,stroke-width:2px;
    classDef datos fill:#e2e3e5,stroke:#6c757d,stroke-width:2px;

    subgraph "PC 2 / 3: Clientes"
        A[👤 Administrador]:::cliente
        J[🎮 Jugador]:::cliente
    end

    subgraph "PC 1: Nodo Servidor Principal"
        SC{🖥️ Servidor Central\n(GenServer)}:::servidor
        Reg[🗂️ Registro de Sorteos\n(Registry)]:::proceso
        S1((🎲 Sorteo Extraordinario\nGenServer)):::proceso
        S2((🎲 Sorteo Navideño\nGenServer)):::proceso
        
        SC -.-> |Busca la dirección| Reg
        Reg -.-> S1
        Reg -.-> S2
    end

    subgraph "Persistencia (Disco Duro)"
        DB_J[(Archivos JSON\nJugadores)]:::datos
        DB_S[(Archivos JSON\nSorteos)]:::datos
    end

    %% Interacciones del Administrador
    A ==>|1. Crea y configura| SC
    A ==>|4. Dispara fecha sistema| SC

    %% Interacciones del Jugador
    J ==>|2. Se registra y consulta| SC
    J ==>|3. Compra billetes| SC

    %% Flujos internos del Servidor
    SC -->|Valida y guarda| DB_J
    SC -->|Delega compras| S1
    SC -->|Delega compras| S2
    
    %% Acciones de los sorteos
    S1 -->|Guarda estado de ventas| DB_S
    S2 -->|Guarda estado de ventas| DB_S
    
    %% Flujo final (Sorteo)
    S1 -.->|Envía notificaciones de premio| DB_J
