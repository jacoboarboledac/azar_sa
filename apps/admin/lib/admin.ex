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
end