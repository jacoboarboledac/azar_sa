defmodule Admin do
  @moduledoc """
  Módulo para enviar comandos de administración al Servidor Central.
  """

  def conectar(ip_servidor) do
    nodo = String.to_atom("nodo_servidor@" <> ip_servidor)
    Application.put_env(:admin, :nodo_servidor, nodo)
    
    case Node.ping(nodo) do
      :pong -> IO.puts(IO.ANSI.green() <> "Conectado exitosamente al servidor: #{nodo}" <> IO.ANSI.reset())
      :pang -> IO.puts(IO.ANSI.red() <> "Falló la conexión. Verifica la IP y la cookie." <> IO.ANSI.reset())
    end
  end

  defp obtener_nodo() do
    Application.get_env(:admin, :nodo_servidor, :"nodo_servidor@127.0.0.1")
  end

  def crear_sorteo(nombre, fecha, cantidad_billetes, fracciones, valor) do
    datos = %{
      "nombre" => nombre,
      "fecha" => fecha,
      "cantidad_billetes" => cantidad_billetes,
      "fracciones" => fracciones,
      "valor" => valor
    }
    enviar_mensaje({:crear_sorteo, "Admin", datos})
  end

  def agregar_premio(nombre_sorteo, nombre_premio, valor_premio) do
    premio = %{"nombre" => nombre_premio, "valor" => valor_premio}
    enviar_mensaje({:agregar_premio, "Admin", nombre_sorteo, premio})
  end

  def eliminar_premio(nombre_sorteo, nombre_premio) do
    enviar_mensaje({:eliminar_premio, "Admin", nombre_sorteo, nombre_premio})
  end

  def eliminar_sorteo(nombre_sorteo) do
    enviar_mensaje({:eliminar_sorteo, "Admin", nombre_sorteo})
  end

  def actualizar_fecha(fecha) do
    enviar_mensaje({:actualizar_fecha, "Admin", fecha})
  end

  defp enviar_mensaje(mensaje) do
    case GenServer.call({:servidor_central, obtener_nodo()}, mensaje) do
      {:ok, respuesta} -> 
        IO.puts(IO.ANSI.green() <> "Éxito: " <> respuesta <> IO.ANSI.reset())
      {:error, razon} -> 
        IO.puts(IO.ANSI.red() <> "Error: " <> razon <> IO.ANSI.reset())
    end
  end

  @doc """
  Consulta y muestra los clientes de un sorteo agrupados y ordenados, 
  junto con el total de ingresos generados por ventas.
  """
  def reporte_sorteo(nombre_sorteo) do
    case GenServer.call({:servidor_central, obtener_nodo()}, {:reporte_sorteo, nombre_sorteo}) do
      {:ok, reporte} ->
        IO.puts(IO.ANSI.cyan() <> "\n================================================" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.bright() <> "📊 REPORTE FINANCIERO Y DE CLIENTES: #{nombre_sorteo}" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.cyan() <> "================================================" <> IO.ANSI.reset())
        
        # REQUERIMIENTO: Consultar ingresos por sorteo
        IO.puts("💰 Ingresos totales recaudados: #{IO.ANSI.green()}$#{reporte.ingresos}#{IO.ANSI.reset()}")
        IO.puts(IO.ANSI.light_black() <> "------------------------------------------------" <> IO.ANSI.reset())
        
        # REQUERIMIENTO: Compradores de billete completo (Ordenados alfabéticamente)
        IO.puts(IO.ANSI.magenta() <> "\n🎫 COMPRADORES DE BILLETE COMPLETO:" <> IO.ANSI.reset())
        case reporte.completos do
          [] -> IO.puts("  No hay compras de billetes completos.")
          lista -> 
            Enum.each(lista, fn c -> 
              IO.puts("  👤 #{c.nombre} (Doc: #{c.documento}) -> Compró el Billete ##{c.numero}")
            end)
        end

        # REQUERIMIENTO: Compradores por fracción (Ordenados alfabéticamente)
        IO.puts(IO.ANSI.yellow() <> "\n🎟️ COMPRADORES POR FRACCIÓN:" <> IO.ANSI.reset())
        case reporte.fracciones do
          [] -> IO.puts("  No hay compras por fracciones.")
          lista -> 
            Enum.each(lista, fn c -> 
              IO.puts("  👤 #{c.nombre} (Doc: #{c.documento}) -> Compró #{c.fracciones} fracc. del Billete ##{c.numero}")
            end)
        end
        IO.puts(IO.ANSI.cyan() <> "\n================================================\n" <> IO.ANSI.reset())

      {:error, razon} ->
        IO.puts(IO.ANSI.red() <> "❌ Error: " <> razon <> IO.ANSI.reset())
    end
  end
  @doc """
  REQUERIMIENTO: Consultar premios entregados en un sorteo pasado específico.
  Muestra premios, ganadores con nombres, dinero recolectado y balance (ganancia/pérdida).
  """
  def consultar_premios_pasados(nombre_sorteo) do
    case GenServer.call({:servidor_central, obtener_nodo()}, {:reporte_premios, nombre_sorteo}) do
      {:ok, m} ->
        IO.puts(IO.ANSI.cyan() <> "\n========================================================" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.bright() <> "🏆 AUDITORÍA DE PREMIOS ENTREGADOS: #{m.nombre} (#{m.fecha})" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.cyan() <> "========================================================" <> IO.ANSI.reset())
        IO.puts("💰 Dinero Total Recolectado: #{IO.ANSI.green()}$#{m.dinero_recolectado}#{IO.ANSI.reset()}")
        IO.puts("💸 Total Dinero Pagado en Premios: #{IO.ANSI.red()}$#{m.total_premios_pagados}#{IO.ANSI.reset()}")
        
        # Calcular e indicar ganancia o pérdida
        if m.balance >= 0 do
          IO.puts("📈 Estado Financiero: #{IO.ANSI.green()}GANANCIA de $#{m.balance}#{IO.ANSI.reset()}")
        else
          IO.puts("📉 Estado Financiero: #{IO.ANSI.red()}PÉRDIDA de $#{abs(m.balance)} (El fondo cubrió el faltante)#{IO.ANSI.reset()}")
        end
        IO.puts(IO.ANSI.light_black() <> "--------------------------------------------------------" <> IO.ANSI.reset())

        IO.puts(IO.ANSI.yellow() <> "\n✨ DESGLOSE DE PREMIOS Y GANADORES:" <> IO.ANSI.reset())
        Enum.each(m.premios, fn p ->
          IO.puts("\n🎁 Premio: #{p.nombre_premio} (Valor Base: $#{p.valor_base_premio})")
          IO.puts("   🎯 Número Ganador: ##{p.numero_ganador}")
          
          case p.ganadores do
            [] -> 
              IO.puts("   👤 Ganadores: #{IO.ANSI.light_black()}Ninguno (El premio quedó vacante, la empresa retiene el dinero).#{IO.ANSI.reset()}")
            lista ->
              Enum.each(lista, fn g ->
                IO.puts("   👤 Ganador: #{g.nombre} (Doc: #{g.documento}) -> Poseía #{g.fracciones} fracc. | Cobró: #{IO.ANSI.green()}$#{g.dinero_entregado}#{IO.ANSI.reset()}")
              end)
              IO.puts("   💵 Total desembolsado para este premio: $#{p.total_pagado}")
          end
        end)
        IO.puts(IO.ANSI.cyan() <> "\n========================================================\n" <> IO.ANSI.reset())

      {:error, razon} ->
        IO.puts(IO.ANSI.red() <> "❌ Error: " <> razon <> IO.ANSI.reset())
    end
  end

  @doc """
  REQUERIMIENTO: Consultar balance de todos los sorteos pasados.
  Muestra las ganancias o pérdidas por sorteo y un gran resumen total acumulado.
  """
  def consultar_balance_general() do
    case GenServer.call({:servidor_central, obtener_nodo()}, :balance_general) do
      {:ok, data} ->
        IO.puts(IO.ANSI.cyan() <> "\n========================================================" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.bright() <> "📊 BALANCE GENERAL HISTÓRICO DE SORTEOS PASADOS" <> IO.ANSI.reset())
        IO.puts(IO.ANSI.cyan() <> "========================================================" <> IO.ANSI.reset())
        
        if data.sorteos == [] do
          IO.puts(IO.ANSI.yellow() <> "No hay registros de sorteos finalizados en el sistema." <> IO.ANSI.reset())
        else
          # Listar balance por sorteo
          Enum.each(data.sorteos, fn s ->
            tipo_balance = if s.balance >= 0, do: "#{IO.ANSI.green()}GANANCIA: $#{s.balance}", else: "#{IO.ANSI.red()}PÉRDIDA: -$#{abs(s.balance)}"
            IO.puts("🎲 Sorteo: #{String.pad_trailing(s.nombre, 15)} | Fecha: #{s.fecha} | #{tipo_balance}#{IO.ANSI.reset()}")
          end)
          
          IO.puts(IO.ANSI.light_black() <> "--------------------------------------------------------" <> IO.ANSI.reset())
          # Gran resumen total acumulado
          IO.puts(IO.ANSI.bright() <> "🏛️ RESUMEN CONSOLIDADO DE LA EMPRESA:" <> IO.ANSI.reset())
          IO.puts("📥 Total Recaudado Histórico : #{IO.ANSI.green()}$#{data.resumen.recolectado}#{IO.ANSI.reset()}")
          IO.puts("📤 Total Pagado en Premios   : #{IO.ANSI.red()}$#{data.resumen.pagado}#{IO.ANSI.reset()}")
          
          if data.resumen.balance >= 0 do
            IO.puts("💰 UTILIDAD NETO ACUMULADA   : #{IO.ANSI.green()}$#{data.resumen.balance} (Superávit)#{IO.ANSI.reset()}")
          else
            IO.puts("🚨 DÉFICIT NETO ACUMULADO    : #{IO.ANSI.red()}-$#{abs(data.resumen.balance)} (Déficit)#{IO.ANSI.reset()}")
          end
        end
        IO.puts(IO.ANSI.cyan() <> "========================================================\n" <> IO.ANSI.reset())

      {:error, razon} ->
        IO.puts(IO.ANSI.red() <> "❌ Error: " <> razon <> IO.ANSI.reset())
    end
  end
end