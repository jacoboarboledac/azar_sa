defmodule Servidor.Central do
  use GenServer

  # --- API Cliente ---
  
  @doc """
  Inicia el servidor central y lo registra con el nombre :servidor_central
  para que cualquier nodo pueda encontrarlo por su nombre.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: :servidor_central)
  end

  # --- Callbacks del Servidor ---

  @impl true
  def init(estado) do
    IO.puts("Servidor Central iniciado y esperando solicitudes...")
    {:ok, estado}
  end

  @impl true
  def handle_call({:crear_sorteo, modulo_cliente, datos_sorteo}, _from, estado) do
    # Extraemos el nombre del mapa para los mensajes
    nombre_sorteo = datos_sorteo["nombre"]

    # Le pasamos el mapa completo al supervisor
    resultado = case Servidor.SupervisorSorteos.iniciar_sorteo(datos_sorteo) do
      {:ok, _pid} -> 
        {:ok, "Sorteo '#{nombre_sorteo}' creado exitosamente."}
      {:error, {:already_started, _pid}} -> 
        {:error, "El sorteo '#{nombre_sorteo}' ya existe y está corriendo."}
      error -> 
        {:error, "Fallo al crear sorteo: #{inspect(error)}"}
    end

    registrar_bitacora(modulo_cliente, "Crear Sorteo: #{nombre_sorteo}", resultado)
    {:reply, resultado, estado}
  end
  @impl true
  def handle_call({:crear_premio, modulo_cliente, nombre_sorteo, datos_premio}, _from, estado) do
    # Generamos la "dirección" (PID) del sorteo usando el Registry
    direccion_sorteo = {:via, Registry, {Servidor.RegistroSorteos, nombre_sorteo}}

    # Intentamos enviarle el mensaje directamente al sorteo
    resultado = try do
      GenServer.call(direccion_sorteo, {:agregar_premio, datos_premio})
    catch
      # Si el proceso no existe o está apagado, atrapamos el error
      :exit, _ -> {:error, "El sorteo '#{nombre_sorteo}' no está activo o no existe."}
    end

    # Registramos en la bitácora central el resultado
    accion = "Agregar premio '#{datos_premio["nombre"]}' a '#{nombre_sorteo}'"
    registrar_bitacora(modulo_cliente, accion, resultado)
    
    {:reply, resultado, estado}
  end
  @impl true
  def handle_call({:solicitud, modulo_cliente, accion}, _from, estado) do
    # Aquí procesaremos la acción. Por ahora, responderemos con un mensaje de prueba.
    resultado = procesar_accion(accion)
    
    # Registramos la actividad cumpliendo el requerimiento del proyecto
    registrar_bitacora(modulo_cliente, accion, resultado)
    
    # Respondemos al cliente
    {:reply, resultado, estado}
  end
  @impl true
  def handle_call({:eliminar_premio, modulo_cliente, nombre_sorteo, nombre_premio}, _from, estado) do
    direccion_sorteo = {:via, Registry, {Servidor.RegistroSorteos, nombre_sorteo}}
    resultado = try do
      GenServer.call(direccion_sorteo, {:eliminar_premio, nombre_premio})
    catch
      :exit, _ -> {:error, "El sorteo '#{nombre_sorteo}' no está activo o no existe."}
    end

    registrar_bitacora(modulo_cliente, "Eliminar premio '#{nombre_premio}' en '#{nombre_sorteo}'", resultado)
    {:reply, resultado, estado}
  end

  @impl true
  def handle_call({:eliminar_sorteo, modulo_cliente, nombre_sorteo}, _from, estado) do
    direccion_sorteo = {:via, Registry, {Servidor.RegistroSorteos, nombre_sorteo}}
    resultado = try do
      GenServer.call(direccion_sorteo, :intentar_eliminar_sorteo)
    catch
      :exit, _ -> {:error, "El sorteo '#{nombre_sorteo}' no está activo o no existe."}
    end

    registrar_bitacora(modulo_cliente, "Eliminar sorteo '#{nombre_sorteo}'", resultado)
    {:reply, resultado, estado}
  end
  @impl true
  def handle_call({:registrar_jugador, datos_jugador}, _from, estado) do
    documento = datos_jugador["documento"]
    
    # Verificamos si el jugador ya existe para no duplicarlo
    resultado = case Servidor.Persistencia.cargar_jugador(documento) do
      {:ok, _datos_existentes} -> 
        {:error, "El jugador con documento '#{documento}' ya está registrado."}
        
      {:error, :no_existe} ->
        # Si no existe, lo guardamos
        Servidor.Persistencia.guardar_jugador(documento, datos_jugador)
        {:ok, "Jugador '#{datos_jugador["nombre"]}' registrado exitosamente."}
    end

    # Guardamos en la bitácora
    registrar_bitacora("Jugador", "Registro de nuevo usuario: #{documento}", resultado)
    {:reply, resultado, estado}
  end

  @impl true
  def handle_call(:consultar_sorteos, _from, estado) do
    # Calculamos la ruta de la carpeta de sorteos
    ruta_sorteos = Path.join([File.cwd!(), "..", "..", "data", "sorteos"]) |> Path.expand()
    
    # Leemos la carpeta y extraemos la información
    lista_sorteos = if File.exists?(ruta_sorteos) do
      File.ls!(ruta_sorteos)
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(fn archivo ->
        nombre_sorteo = String.replace(archivo, ".json", "")
        # Cargamos los datos de cada archivo para armar el resumen
        {:ok, datos} = Servidor.Persistencia.cargar(nombre_sorteo)
        %{
          "nombre" => datos["nombre"],
          "fecha" => datos["fecha"],
          "valor" => datos["valor"]
        }
      end)
    else
      [] # Si no existe la carpeta, devolvemos una lista vacía
    end

    {:reply, {:ok, lista_sorteos}, estado}
  end
  @impl true
  def handle_call({:comprar_billete, doc, password, nombre_sorteo, num_billete, fracciones}, _from, estado) do
    # 1. Validar identidad del jugador
    case Servidor.Persistencia.cargar_jugador(doc) do
      {:ok, jugador} ->
        if jugador["password"] == password do
          
          # 2. Si la contraseña es correcta, intentamos comprar en el Sorteo
          dir_sorteo = {:via, Registry, {Servidor.RegistroSorteos, nombre_sorteo}}
          try do
            case GenServer.call(dir_sorteo, {:comprar_billete, doc, num_billete, fracciones}) do
              {:ok, _msj_sorteo} ->
                # 3. Si el sorteo aceptó, le agregamos el billete al JSON del jugador
                compra = %{"sorteo" => nombre_sorteo, "numero" => num_billete, "fracciones" => fracciones}
                jugador_actualizado = Map.put(jugador, "billetes_comprados", [compra | jugador["billetes_comprados"]])
                Servidor.Persistencia.guardar_jugador(doc, jugador_actualizado)

                registrar_bitacora("Jugador #{doc}", "Compra billete #{num_billete} en #{nombre_sorteo}", {:ok, "Éxito"})
                {:reply, {:ok, "¡Compra exitosa! Tienes #{fracciones} fracción(es) del billete #{num_billete}."}, estado}
                
              {:error, razon} ->
                {:reply, {:error, razon}, estado}
            end
          catch
            :exit, _ -> {:reply, {:error, "El sorteo '#{nombre_sorteo}' no está activo o no existe."}, estado}
          end
        else
          {:reply, {:error, "Contraseña incorrecta."}, estado}
        end
        
      {:error, :no_existe} ->
        {:reply, {:error, "El jugador con documento #{doc} no existe."}, estado}
    end
  end
  @impl true
  def handle_call({:actualizar_fecha, modulo_cliente, fecha}, _from, estado) do
    ruta_sorteos = Path.join([File.cwd!(), "..", "..", "data", "sorteos"]) |> Path.expand()
    
    if File.exists?(ruta_sorteos) do
      # Leemos los archivos de sorteos
      archivos = File.ls!(ruta_sorteos) |> Enum.filter(&String.ends_with?(&1, ".json"))
      
      # Revisamos uno por uno
      sorteos_jugados = Enum.reduce(archivos, 0, fn archivo, acc ->
        nombre_sorteo = String.replace(archivo, ".json", "")
        {:ok, datos} = Servidor.Persistencia.cargar(nombre_sorteo)
        
        # Filtramos por fecha y que no haya sido jugado ya
        if datos["fecha"] == fecha and Map.get(datos, "estado") != "finalizado" do
           dir_sorteo = {:via, Registry, {Servidor.RegistroSorteos, nombre_sorteo}}
           try do
             GenServer.call(dir_sorteo, :ejecutar_sorteo)
             acc + 1 # Sumamos 1 al contador de sorteos jugados
           catch
             :exit, _ -> acc
           end
        else
          acc
        end
      end)
      
      resultado = {:ok, "Se encontraron y ejecutaron #{sorteos_jugados} sorteos para la fecha #{fecha}."}
      registrar_bitacora(modulo_cliente, "Actualizar fecha a #{fecha}", resultado)
      {:reply, resultado, estado}
    else
      {:reply, {:error, "No hay sorteos registrados."}, estado}
    end
  end
  @impl true
  def handle_call({:consultar_notificaciones, doc, password}, _from, estado) do
    case Servidor.Persistencia.cargar_jugador(doc) do
      {:ok, jugador} ->
        if jugador["password"] == password do
          # Obtenemos las notificaciones (si no tiene, devolvemos lista vacía)
          notificaciones = Map.get(jugador, "notificaciones", [])
          {:reply, {:ok, notificaciones}, estado}
        else
          {:reply, {:error, "Contraseña incorrecta."}, estado}
        end
        
      {:error, :no_existe} ->
        {:reply, {:error, "El jugador con documento #{doc} no existe."}, estado}
    end
  end
  # --- Funciones Privadas ---

  defp procesar_accion(accion) do
    # Más adelante, aquí enrutaremos a los servidores de cada sorteo
    {:ok, "Recibí tu solicitud de: #{accion}"}
  end

  defp registrar_bitacora(cliente, accion, resultado) do
    # Obtenemos la fecha y hora actual
    fecha_hora = NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second) |> to_string()
    
    # Formateamos el mensaje según lo pedido en el proyecto
    estatus = case resultado do
      {:ok, _} -> "ok"
      {:error, _} -> "negado"
      _ -> "ok"
    end
    
    mensaje_log = "[#{fecha_hora}] Cliente: #{cliente} | Solicitud: #{accion} | Resultado: #{estatus}\n"
    
    # Mostramos en pantalla
    IO.puts(IO.ANSI.cyan() <> mensaje_log <> IO.ANSI.reset())
    
    # Guardamos en el archivo bitacora.txt (agregando al final con :append)
    File.write!("bitacora.txt", mensaje_log, [:append])
  end
  
end
