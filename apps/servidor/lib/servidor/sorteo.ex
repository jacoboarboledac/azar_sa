defmodule Servidor.Sorteo do
  use GenServer
  alias Servidor.Persistencia

  # Ahora recibimos el mapa completo de datos_sorteo
  def start_link(datos_sorteo) do
    nombre = datos_sorteo["nombre"]
    GenServer.start_link(__MODULE__, datos_sorteo, name: via_tuple(nombre))
  end

  @impl true
  def init(datos_sorteo) do
    nombre = datos_sorteo["nombre"]
    IO.puts(IO.ANSI.yellow() <> "Levantando servidor independiente para sorteo: #{nombre}" <> IO.ANSI.reset())
    
    estado = case Persistencia.cargar(nombre) do
      {:ok, datos_guardados} ->
        IO.puts(IO.ANSI.green() <> "-> Cargando datos existentes de '#{nombre}' desde JSON." <> IO.ANSI.reset())
        datos_guardados
        
      {:error, :no_existe} ->
        IO.puts(IO.ANSI.cyan() <> "-> Creando nuevo archivo JSON para '#{nombre}'..." <> IO.ANSI.reset())
        # Guardamos el mapa completo que nos envió el Admin
        Persistencia.guardar(nombre, datos_sorteo)
        datos_sorteo
    end
    
    {:ok, estado}
  end

  defp via_tuple(nombre) do
    {:via, Registry, {Servidor.RegistroSorteos, nombre}}
  end
  # --- Callbacks del Sorteo ---

  @impl true
  def handle_call({:agregar_premio, datos_premio}, _from, estado) do
    # 1. Obtenemos la lista actual de premios y le agregamos el nuevo
    premios_actualizados = [datos_premio | estado["premios"]]
    
    # 2. Actualizamos el mapa del estado
    nuevo_estado = Map.put(estado, "premios", premios_actualizados)
    
    # 3. Guardamos el nuevo estado en el archivo JSON
    Persistencia.guardar(estado["nombre"], nuevo_estado)
    
    {:reply, {:ok, "Premio agregado correctamente al sorteo."}, nuevo_estado}
  end
  @impl true
  def handle_call({:eliminar_premio, nombre_premio}, _from, estado) do
    # Regla: No eliminar premio si ya hay billetes vendidos
    if length(estado["billetes_vendidos"]) > 0 do
      {:reply, {:error, "Negado: El sorteo ya tiene clientes/billetes vendidos."}, estado}
    else
      # Filtramos la lista para quitar el premio que coincida con el nombre
      premios_restantes = Enum.reject(estado["premios"], fn p -> p["nombre"] == nombre_premio end)
      
      if length(premios_restantes) == length(estado["premios"]) do
         {:reply, {:error, "Negado: El premio '#{nombre_premio}' no existe."}, estado}
      else
         nuevo_estado = Map.put(estado, "premios", premios_restantes)
         Persistencia.guardar(estado["nombre"], nuevo_estado)
         {:reply, {:ok, "Premio eliminado correctamente."}, nuevo_estado}
      end
    end
  end

  @impl true
  def handle_call(:intentar_eliminar_sorteo, _from, estado) do
    # Regla: No eliminar sorteo si tiene premios asociados
    if length(estado["premios"]) > 0 do
      {:reply, {:error, "Negado: No se puede eliminar el sorteo porque tiene premios asociados."}, estado}
    else
      # Cumple la regla: Borramos el archivo JSON
      Persistencia.eliminar(estado["nombre"])
      
      # Esta tupla especial le dice a Elixir:
      # :stop -> Apaga este proceso de sorteo
      # :normal -> Se apaga sin errores
      # {:ok, ...} -> Lo que le respondemos al cliente
      {:stop, :normal, {:ok, "Sorteo y archivo eliminados exitosamente."}, estado}
    end
  end
  @impl true
  def handle_call({:comprar_billete, documento, numero_billete, cant_fracciones}, _from, estado) do
    # 1. Validar que el número de billete esté en el rango permitido
    if numero_billete < 1 or numero_billete > estado["cantidad_billetes"] do
      {:reply, {:error, "El billete #{numero_billete} no existe en este sorteo."}, estado}
    else
      # 2. Calcular cuántas fracciones ya se han vendido de ese mismo billete
      vendidas_previamente = estado["billetes_vendidos"]
        |> Enum.filter(fn b -> b["numero"] == numero_billete end)
        |> Enum.reduce(0, fn b, acc -> acc + b["fracciones"] end)

      # 3. Validar si quedan suficientes fracciones disponibles
      if vendidas_previamente + cant_fracciones > estado["fracciones"] do
        {:reply, {:error, "No hay suficientes fracciones disponibles para el billete #{numero_billete}."}, estado}
      else
        # 4. Registrar la venta en el estado del sorteo y guardar el JSON
        nueva_venta = %{
          "documento" => documento,
          "numero" => numero_billete,
          "fracciones" => cant_fracciones
        }
        nuevo_estado = Map.put(estado, "billetes_vendidos", [nueva_venta | estado["billetes_vendidos"]])
        Persistencia.guardar(estado["nombre"], nuevo_estado)
        
        {:reply, {:ok, "Compra registrada en el sorteo."}, nuevo_estado}
      end
    end
  end
  @impl true
  def handle_call(:ejecutar_sorteo, _from, estado) do
    max_billetes = estado["cantidad_billetes"]
    fracciones_totales = estado["fracciones"]
    nombre_sorteo = estado["nombre"]

    IO.puts(IO.ANSI.magenta() <> "\n🎲 ¡Iniciando sorteo: #{nombre_sorteo}! 🎲" <> IO.ANSI.reset())

    # 1. Identificar participantes únicos para el boletín general
    participantes = estado["billetes_vendidos"]
      |> Enum.map(fn venta -> venta["documento"] end)
      |> Enum.uniq()

    # 2. Sacar balotas y recolectar estructura de resultados para el JSON
    resultados_lista = Enum.map(estado["premios"], fn premio ->
      billete_ganador = Enum.random(1..max_billetes)
      valor_por_fraccion = premio["valor"] / fracciones_totales
      
      # Filtrar quiénes compraron ese número específico
      ganadores_proceso = Enum.filter(estado["billetes_vendidos"], fn b -> b["numero"] == billete_ganador end)
      documentos_ganadores = Enum.map(ganadores_proceso, fn g -> g["documento"] end) |> Enum.uniq()

      # Enviar notificación privada de dinero a los ganadores
      Enum.each(ganadores_proceso, fn g ->
        pago_total = g["fracciones"] * valor_por_fraccion
        mensaje_ganador = "🏆 ¡Ganaste $#{pago_total} en #{nombre_sorteo}! (Premio: #{premio["nombre"]})"
        Servidor.Persistencia.agregar_notificacion_jugador(g["documento"], mensaje_ganador)
      end)

      # Estructura que guardaremos en el archivo del sorteo
      %{
        "premio_nombre" => premio["nombre"],
        "numero_ganador" => billete_ganador,
        "ganadores" => documentos_ganadores
      }
    end)

    # 3. Enviar boletín informativo general a todos los participantes
    texto_boletin = Enum.map(resultados_lista, fn r -> "#{r["premio_nombre"]}: ##{r["numero_ganador"]}" end) |> Enum.join(" | ")
    mensaje_general = "📢 Resultados de #{nombre_sorteo} -> " <> texto_boletin
    Enum.each(participantes, fn documento ->
      Servidor.Persistencia.agregar_notificacion_jugador(documento, mensaje_general)
    end)
    
    # 4. Guardar TODO en el estado e inyectarlo en el JSON
    nuevo_estado = estado
      |> Map.put("estado", "finalizado")
      |> Map.put("resultados", resultados_lista) # <-- AQUÍ GUARDAMOS LOS GANADORES

    Persistencia.guardar(nombre_sorteo, nuevo_estado)

    {:reply, {:ok, "Sorteo ejecutado y resultados registrados."}, nuevo_estado}
  end
end