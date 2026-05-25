defmodule Jugador do
  @moduledoc """
  Módulo principal para las operaciones del cliente/jugador.
  """

  @doc """
  Configura la IP del servidor al que nos vamos a conectar y hace la prueba de red.
  Ejemplo: Jugador.conectar("192.168.1.50")
  """
  def conectar(ip_servidor) do
    nodo = String.to_atom("nodo_servidor@" <> ip_servidor)
    Application.put_env(:jugador, :nodo_servidor, nodo)
    
    case Node.ping(nodo) do
      :pong -> IO.puts(IO.ANSI.green() <> "✅ Conectado exitosamente al servidor: #{nodo}" <> IO.ANSI.reset())
      :pang -> IO.puts(IO.ANSI.red() <> "❌ Falló la conexión. Verifica la IP, la cookie de red o el Firewall." <> IO.ANSI.reset())
    end
  end

  # Función privada para obtener el nodo guardado en memoria
  defp obtener_nodo() do
    Application.get_env(:jugador, :nodo_servidor, :"nodo_servidor@127.0.0.1")
  end

  def registrar(nombre, documento, password, tarjeta) do
    datos_jugador = %{
      "nombre" => nombre,
      "documento" => documento,
      "password" => password,
      "tarjeta" => tarjeta,
      "billetes_comprados" => []
    }

    case GenServer.call({:servidor_central, obtener_nodo()}, {:registrar_jugador, datos_jugador}) do
      {:ok, respuesta} -> IO.puts(IO.ANSI.green() <> "Éxito: " <> respuesta <> IO.ANSI.reset())
      {:error, razon} -> IO.puts(IO.ANSI.red() <> "Error: " <> razon <> IO.ANSI.reset())
    end
  end

  def consultar_sorteos() do
    case GenServer.call({:servidor_central, obtener_nodo()}, :consultar_sorteos) do
      {:ok, []} -> 
        IO.puts(IO.ANSI.yellow() <> "No hay sorteos registrados en el sistema." <> IO.ANSI.reset())
      {:ok, sorteos} ->
        IO.puts(IO.ANSI.cyan() <> "\n=========================================" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.cyan() <> "🏛️      CARTELERA OFICIAL DE SORTEOS     🏛️" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.cyan() <> "=========================================" <> IO.ANSI.reset())

        # REQUERIMIENTO: Ordenados por fecha
        sorteos_ordenados = Enum.sort_by(sorteos, fn s -> s["fecha"] end)

        Enum.each(sorteos_ordenados, fn sorteo ->
          estado_tag = if sorteo["estado"] == "finalizado", do: "🔴 [FINALIZADO]", edit: "🟢 [ACTIVO]"
          estado_tag = if sorteo["estado"] == "finalizado", do: "[FINALIZADO 🛑]", else: "[ACTIVO 🟢]"
          
          IO.puts("\n🎲 Sorteo: #{IO.ANSI.bright()}#{sorteo["nombre"]}#{IO.ANSI.reset()} #{estado_tag}")
          IO.puts("📅 Fecha: #{sorteo["fecha"]} | 💰 Valor Fracción: $#{sorteo["valor"]}")
          
          # REQUERIMIENTO: Mostrar premios asociados (si existen)
          case sorteo["premios"] do
            [] -> IO.puts("  🎁 Premios: Sin premios configurados.")
            premios -> 
              IO.puts("  🎁 Premios asociados:")
              Enum.each(premios, fn p -> IO.puts("     • #{p["nombre"]}: $#{p["valor"]}") end)
          end

          # REQUERIMIENTO: Si el sorteo ya se realizó, mostrar números ganadores e indicar ganadores por premio
          if sorteo["estado"] == "finalizado" do
            IO.puts(IO.ANSI.yellow() <> "  📊 RESULTADOS DEL SORTEO:" <> IO.ANSI.reset())
            case sorteo["resultados"] do
              nil -> IO.puts("     No se registraron datos del escrutinio.")
              resultados ->
                Enum.each(resultados, fn res ->
                  IO.puts("     ✨ #{res["premio_nombre"]} -> Número Ganador: #{IO.ANSI.green()}##{res["numero_ganador"]}#{IO.ANSI.reset()}")
                  
                  case res["ganadores"] do
                    [] -> IO.puts("        👤 Ganadores: ¡Nadie compró este número! El premio queda vacante.")
                    lista -> 
                      ganadores_str = Enum.join(lista, ", ")
                      IO.puts("        👤 Ganadores (Cédulas): #{IO.ANSI.bright()}#{ganadores_str}#{IO.ANSI.reset()}")
                  end
                end)
            end
          end
          IO.puts(IO.ANSI.light_black() <> "-----------------------------------------" <> IO.ANSI.reset())
        end)
      {:error, razon} ->
        IO.puts(IO.ANSI.red() <> "❌ Error al consultar: " <> razon <> IO.ANSI.reset())
    end
  end

  def comprar_billete(documento, password, nombre_sorteo, numero_billete, fracciones) do
    mensaje = {:comprar_billete, documento, password, nombre_sorteo, numero_billete, fracciones}
    case GenServer.call({:servidor_central, obtener_nodo()}, mensaje) do
      {:ok, respuesta} -> IO.puts(IO.ANSI.green() <> "🎉 " <> respuesta <> IO.ANSI.reset())
      {:error, razon} -> IO.puts(IO.ANSI.red() <> "❌ Error: " <> razon <> IO.ANSI.reset())
    end
  end

  def revisar_notificaciones(documento, password) do
    case GenServer.call({:servidor_central, obtener_nodo()}, {:consultar_notificaciones, documento, password}) do
      {:ok, []} ->
        IO.puts(IO.ANSI.yellow() <> "📭 No tienes notificaciones nuevas." <> IO.ANSI.reset())
      {:ok, notas} ->
        IO.puts(IO.ANSI.cyan() <> "\n=== 🏆 TUS NOTIFICACIONES 🏆 ===" <> IO.ANSI.reset())
        Enum.each(notas, fn nota -> IO.puts("💌 " <> nota) end)
        IO.puts(IO.ANSI.cyan() <> "================================\n" <> IO.ANSI.reset())
      {:error, razon} ->
        IO.puts(IO.ANSI.red() <> "❌ Error: " <> razon <> IO.ANSI.reset())
    end
  end
  @doc """
  REQUERIMIENTO: Listar todos los premios del sistema.
  Muestra la información agrupada por sorteo y ordenada cronológicamente por fecha.
  """
  def consultar_premios() do
    case GenServer.call({:servidor_central, obtener_nodo()}, :listar_premios_agrupados) do
      {:ok, sorteos} ->
        IO.puts(IO.ANSI.cyan() <> "\n========================================================" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.bright() <> "🏆             PLAN GLOBAL DE PREMIOS OFRECIDOS          🏆" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.cyan() <> "========================================================" <> IO.ANSI.reset())
        
        if sorteos == [] do
          IO.puts(IO.ANSI.yellow() <> "No hay sorteos ni premios registrados en el sistema." <> IO.ANSI.reset())
        else
          Enum.each(sorteos, fn s ->
            status_color = if s["estado"] == "finalizado", do: IO.ANSI.red() <> "[CERRADO]", else: IO.ANSI.green() <> "[VIGENTE]"
            
            # REQUERIMIENTO: Agrupados por sorteo (Mostramos el encabezado del sorteo)
            IO.puts("\n📅 Fecha: #{s["fecha"]} | 🎲 Sorteo: #{IO.ANSI.bright()}#{s["nombre"]}#{IO.ANSI.reset()} #{status_color}#{IO.ANSI.reset()}")
            
            case s["premios"] do
              [] -> 
                IO.puts("   " <> IO.ANSI.light_black() <> "Este sorteo no cuenta con premios configurados." <> IO.ANSI.reset())
              premios ->
                # Listar los premios pertenecientes a este grupo/sorteo
                Enum.each(premios, fn p ->
                  IO.puts("   • 🎁 #{String.pad_trailing(p["nombre"], 22)} -> Monto Prometido: #{IO.ANSI.green()}$#{p["valor"]}#{IO.ANSI.reset()}")
                end)
            end
            IO.puts(IO.ANSI.light_black() <> "--------------------------------------------------------" <> IO.ANSI.reset())
          end)
        end
        IO.puts(IO.ANSI.cyan() <> "========================================================\n" <> IO.ANSI.reset())

      {:error, razon} ->
        IO.puts(IO.ANSI.red() <> "❌ Error al obtener premios: " <> razon <> IO.ANSI.reset())
    end
  end
  @doc "REQUERIMIENTO: Consultar sorteos disponibles (Solo activos)"
  def consultar_sorteos_disponibles() do
    case GenServer.call({:servidor_central, obtener_nodo()}, :sorteos_disponibles) do
      {:ok, []} -> IO.puts("ℹ️ No hay sorteos disponibles para jugar en este momento.")
      {:ok, sorteos} ->
        IO.puts("\n🟢 --- SORTEOS DISPONIBLES PARA COMPRAR --- 🟢")
        Enum.each(sorteos, fn s -> 
          IO.puts("🎲 #{s["nombre"]} | Fecha: #{s["fecha"]} | Valor Billete: $#{s["valor"]}")
        end)
    end
  end

  @doc "REQUERIMIENTO: Consultar números disponibles (Completos vs Fraccionados)"
  def consultar_numeros_disponibles(nombre_sorteo) do
    case GenServer.call({:servidor_central, obtener_nodo()}, {:numeros_disponibles, nombre_sorteo}) do
      {:error, razon} -> IO.puts("❌ Error: #{razon}")
      {:ok, listas} ->
        IO.puts("\n📊 DISPONIBILIDAD DE NÚMEROS EN: #{nombre_sorteo}")
        
        IO.puts(IO.ANSI.green() <> "\n🎫 Billetes Completos (Todas sus fracciones libres):" <> IO.ANSI.reset())
        if listas.completos == [], do: IO.puts("  Ninguno."), else: IO.puts("  #{Enum.join(listas.completos, ", ")}")

        IO.puts(IO.ANSI.yellow() <> "\n🎟️ Disponibles por Fracción (Parcialmente vendidos):" <> IO.ANSI.reset())
        if listas.fracciones == [] do
          IO.puts("  Ninguno.")
        else
          Enum.each(listas.fracciones, fn {num, frac_libres} -> 
            IO.puts("  • Número ##{num} -> Le quedan #{frac_libres} fracciones libres.")
          end)
        end
    end
  end

  @doc "REQUERIMIENTO: Historial de compras, Total gastado, Premios obtenidos y Balance personal"
  def consultar_balance_personal(documento) do
    case GenServer.call({:servidor_central, obtener_nodo()}, {:balance_personal_jugador, documento}) do
      {:ok, perfil} ->
        IO.puts(IO.ANSI.cyan() <> "\n========================================================" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.bright() <> "👤 ESTADO DE CUENTA Y BALANCE: JUGADOR #{documento}" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.cyan() <> "========================================================" <> IO.ANSI.reset())
        
        IO.puts("\n📦 HISTORIAL DE COMPRAS REALIZADAS:")
        if perfil.compras == [] do
          IO.puts("  No registras ninguna compra en el sistema.")
        else
          Enum.each(perfil.compras, fn c -> IO.puts("  • #{c}") end)
        end
        
        IO.puts(IO.ANSI.light_black() <> "--------------------------------------------------------" <> IO.ANSI.reset())
        IO.puts("💸 Total Dinero Gastado   : #{IO.ANSI.red()}$#{perfil.gastado}#{IO.ANSI.reset()}")
        IO.puts("🏆 Total Premios Obtenidos: #{IO.ANSI.green()}$#{perfil.premios}#{IO.ANSI.reset()}")
        
        # CÁLCULO DEL BALANCE PERSONAL: (Premios ganados - Dinero Invertido)
        balance_neto = perfil.premios - perfil.gastado
        if balance_neto >= 0 do
          IO.puts("📊 Balance Personal Neto  : #{IO.ANSI.green()}+$#{balance_neto} (Vas Ganando)📈" <> IO.ANSI.reset())
        else
          IO.puts("📊 Balance Personal Neto  : #{IO.ANSI.red()}-$#{abs(balance_neto)} (Inversión no recuperada)📉" <> IO.ANSI.reset())
        end
        IO.puts(IO.ANSI.cyan() <> "========================================================\n" <> IO.ANSI.reset())
    end
  end

  @doc "REQUERIMIENTO: Devolver compras (Solo si el sorteo no se ha jugado)"
  def devolver_compra(documento, nombre_sorteo, numero) do
    case GenServer.call({:servidor_central, obtener_nodo()}, {:devolver_compra, documento, nombre_sorteo, numero}) do
      {:ok, mensaje} -> IO.puts(IO.ANSI.green() <> "✅ #{mensaje}" <> IO.ANSI.reset())
      {:error, razon} -> IO.puts(IO.ANSI.red() <> "❌ Error: #{razon}" <> IO.ANSI.reset())
    end
  end
end