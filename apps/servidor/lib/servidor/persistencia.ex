defmodule Servidor.Persistencia do
  @moduledoc """
  Se encarga de guardar, cargar y eliminar el estado de los sorteos en archivos JSON.
  """

  # Función privada que siempre calcula la ruta correcta a la raíz del paraguas
  defp ruta_archivo(nombre_sorteo) do
    Path.join([File.cwd!(), "..", "..", "data", "sorteos", "#{nombre_sorteo}.json"]) 
    |> Path.expand()
  end

  def guardar(nombre_sorteo, datos) do
    ruta = ruta_archivo(nombre_sorteo)
    
    File.mkdir_p!(Path.dirname(ruta))
    
    json_string = Jason.encode!(datos, pretty: true)
    File.write!(ruta, json_string)
  end

  def cargar(nombre_sorteo) do
    ruta = ruta_archivo(nombre_sorteo)
    
    if File.exists?(ruta) do
      contenido = File.read!(ruta)
      {:ok, Jason.decode!(contenido)}
    else
      {:error, :no_existe}
    end
  end

  def eliminar(nombre_sorteo) do
    ruta = ruta_archivo(nombre_sorteo)
    
    if File.exists?(ruta) do
      File.rm!(ruta)
    end
  end
  #Funciones para Jugadores

  defp ruta_jugador(documento) do
    Path.join([File.cwd!(), "..", "..", "data", "jugadores", "#{documento}.json"]) 
    |> Path.expand()
  end

  def guardar_jugador(documento, datos) do
    ruta = ruta_jugador(documento)
    File.mkdir_p!(Path.dirname(ruta))
    
    json_string = Jason.encode!(datos, pretty: true)
    File.write!(ruta, json_string)
  end

  def cargar_jugador(documento) do
    ruta = ruta_jugador(documento)
    if File.exists?(ruta) do
      contenido = File.read!(ruta)
      {:ok, Jason.decode!(contenido)}
    else
      {:error, :no_existe}
    end
  end
  def agregar_notificacion_jugador(documento, mensaje) do
    case cargar_jugador(documento) do
      {:ok, jugador} ->
        notas_actuales = Map.get(jugador, "notificaciones", [])
        jugador_actualizado = Map.put(jugador, "notificaciones", [mensaje | notas_actuales])
        guardar_jugador(documento, jugador_actualizado)
      _ -> :ok 
    end
  end
end