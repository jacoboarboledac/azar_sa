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
        IO.puts(IO.ANSI.yellow() <> "No hay sorteos disponibles en este momento." <> IO.ANSI.reset())
      {:ok, sorteos} ->
        IO.puts(IO.ANSI.cyan() <> "\n=== CARTELERA DE SORTEOS ===" <> IO.ANSI.reset())
        Enum.each(sorteos, fn sorteo ->
          IO.puts("🎲 #{sorteo["nombre"]} | 📅 Fecha: #{sorteo["fecha"]} | 💰 Precio: $#{sorteo["valor"]}")
        end)
        IO.puts(IO.ANSI.cyan() <> "============================\n" <> IO.ANSI.reset())
      {:error, razon} ->
        IO.puts(IO.ANSI.red() <> "Error: " <> razon <> IO.ANSI.reset())
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
end