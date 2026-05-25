defmodule Servidor.Central do
  use GenServer

  # ====================================================================
  # API CLIENTE
  # ====================================================================
  
  @doc """
  Inicia el servidor central y lo registra con el nombre :servidor_central
  para que cualquier nodo pueda encontrarlo por su nombre.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: :servidor_central)
  end

  # ====================================================================
  # CALLBACKS DEL SERVIDOR (GenServer Init)
  # ====================================================================

  @impl true
  def init(estado) do
    IO.puts("Servidor Central iniciado y esperando solicitudes...")
    {:ok, estado}
  end

  # ====================================================================
  # BLOQUE ÚNICO DE HANDLE_CALLS (Lógica de negocio enrutada)
  # ====================================================================

  @impl true
  def handle_call({:crear_sorteo, modulo_cliente, datos_sorteo}, _from, estado) do
    nombre_sorteo = datos_sorteo["nombre"]

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
    direccion_sorteo = {:via, Registry, {Servidor.RegistroSorteos, nombre_sorteo}}

    resultado = try do
      GenServer.call(direccion_sorteo, {:agregar_premio, datos_premio})
    catch
      :exit, _ -> {:error, "El sorteo '#{nombre_sorteo}' no está activo o no existe."}
    end

    accion = "Agregar premio '#{datos_premio["nombre"]}' a '#{nombre_sorteo}'"
    registrar_bitacora(modulo_cliente, accion, resultado)
    
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
    
    resultado = case Servidor.Persistencia.cargar_jugador(documento) do
      {:ok, _datos_existentes} -> 
        {:error, "El jugador con documento '#{documento}' ya está registrado."}
        
      {:error, :no_existe} ->
        Servidor.Persistencia.guardar_jugador(documento, datos_jugador)
        {:ok, "Jugador '#{datos_jugador["nombre"]}' registrado exitosamente."}
    end

    registrar_bitacora("Jugador", "Registro de nuevo usuario: #{documento}", resultado)
    {:reply, resultado, estado}
  end

  @impl true
  def handle_call(:consultar_sorteos, _from, estado) do
    ruta_sorteos = Path.join([File.cwd!(), "..", "..", "data", "sorteos"]) |> Path.expand()
    
    lista_sorteos = if File.exists?(ruta_sorteos) do
      File.ls!(ruta_sorteos)
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(fn archivo ->
        nombre_sorteo = String.replace(archivo, ".json", "")
        {:ok, datos} = Servidor.Persistencia.cargar(nombre_sorteo)
        %{
          "nombre" => datos["nombre"],
          "fecha" => datos["fecha"],
          "valor" => datos["valor"]
        }
      end)
    else
      []
    end

    {:reply, {:ok, lista_sorteos}, estado}
  end

  @impl true
  def handle_call({:comprar_billete, doc, password, nombre_sorteo, num_billete, fracciones}, _from, estado) do
    case Servidor.Persistencia.cargar_jugador(doc) do
      {:ok, jugador} ->
        if jugador["password"] == password do
          dir_sorteo = {:via, Registry, {Servidor.RegistroSorteos, nombre_sorteo}}
          try do
            case GenServer.call(dir_sorteo, {:comprar_billete, doc, num_billete, fracciones}) do
              {:ok, _msj_sorteo} ->
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
      archivos = File.ls!(ruta_sorteos) |> Enum.filter(&String.ends_with?(&1, ".json"))
      
      sorteos_jugados = Enum.reduce(archivos, 0, fn archivo, acc ->
        nombre_sorteo = String.replace(archivo, ".json", "")
        {:ok, datos} = Servidor.Persistencia.cargar(nombre_sorteo)
        
        if datos["fecha"] == fecha and Map.get(datos, "estado") != "finalizado" do
           dir_sorteo = {:via, Registry, {Servidor.RegistroSorteos, nombre_sorteo}}
           try do
             GenServer.call(dir_sorteo, :ejecutar_sorteo)
             acc + 1
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
  def handle_call({:reporte_sorteo, nombre_sorteo}, _from, estado) do
    case Servidor.Persistencia.cargar_sorteo(nombre_sorteo) do
      {:error, _} -> 
        {:reply, {:error, "El sorteo '#{nombre_sorteo}' no existe."}, estado}
        
      {:ok, sorteo} ->
        ventas = Map.get(sorteo, "billetes_vendidos", [])
        fracciones_totales = sorteo["fracciones"]
        valor_billete = sorteo["valor"]
        precio_fraccion = valor_billete / fracciones_totales

        ingresos = Enum.reduce(ventas, 0, fn venta, acumulado -> 
          acumulado + (venta["fracciones"] * precio_fraccion) 
        end)

        clientes_procesados = Enum.map(ventas, fn v ->
          nombre_real = case Servidor.Persistencia.cargar_jugador(v["documento"]) do
            {:ok, jugador} -> jugador["nombre"]
            _ -> "Desconocido (Solo Doc: #{v["documento"]})"
          end
          
          tipo_compra = if v["fracciones"] == fracciones_totales, do: :completo, else: :fraccion
          
          %{
            nombre: nombre_real,
            documento: v["documento"],
            numero: v["numero"],
            fracciones: v["fracciones"],
            tipo: tipo_compra
          }
        end)

        compradores_completos = clientes_procesados
          |> Enum.filter(fn c -> c.tipo == :completo end)
          |> Enum.sort_by(fn c -> String.downcase(c.nombre) end)

        compradores_fraccion = clientes_procesados
          |> Enum.filter(fn c -> c.tipo == :fraccion end)
          |> Enum.sort_by(fn c -> String.downcase(c.nombre) end)

        reporte = %{
          ingresos: ingresos,
          completos: compradores_completos,
          fracciones: compradores_fraccion
        }

        registrar_bitacora("Admin", "Consultar reporte de clientes e ingresos: #{nombre_sorteo}", {:ok, "Generado"})
        {:reply, {:ok, reporte}, estado}
    end
  end

  @impl true
  def handle_call({:consultar_notificaciones, doc, password}, _from, estado) do
    case Servidor.Persistencia.cargar_jugador(doc) do
      {:ok, jugador} ->
        if jugador["password"] == password do
          notificaciones = Map.get(jugador, "notificaciones", [])
          {:reply, {:ok, notificaciones}, estado}
        else
          {:reply, {:error, "Contraseña incorrecta."}, estado}
        end
        
      {:error, :no_existe} ->
        {:reply, {:error, "El jugador con documento #{doc} no existe."}, estado}
    end
  end

  @impl true
  def handle_call({:reporte_premios, nombre_sorteo}, _from, estado) do
    case Servidor.Persistencia.cargar_sorteo(nombre_sorteo) do
      {:error, _} -> 
        {:reply, {:error, "El sorteo '#{nombre_sorteo}' no existe."}, estado}
      {:ok, sorteo} ->
        if sorteo["estado"] != "finalizado" do
          {:reply, {:error, "El sorteo '#{nombre_sorteo}' no se ha ejecutado aún. No hay premios entregados."}, estado}
        else
          metricas = calcular_metricas_sorteo(sorteo)
          registrar_bitacora("Admin", "Consultar premios entregados: #{nombre_sorteo}", {:ok, "Generado"})
          {:reply, {:ok, metricas}, estado}
        end
    end
  end

  @impl true
  def handle_call(:balance_general, _from, estado) do
    ruta_data = Path.join([File.cwd!(), "..", "..", "data"]) |> Path.expand()
    
    balances_sorteos = case File.ls(ruta_data) do
      {:ok, archivos} ->
        archivos
        |> Enum.filter(fn f -> String.end_with?(f, ".json") and not String.starts_with?(f, "jugador_") end)
        |> Enum.reduce([], fn archivo, acc ->
          path_completo = Path.join(ruta_data, archivo)
          case File.read(path_completo) do
            {:ok, contenido} ->
              case Jason.decode(contenido) do
                {:ok, json} ->
                  if Map.get(json, "estado") == "finalizado" and Map.has_key?(json, "cantidad_billetes") do
                    [calcular_metricas_sorteo(json) | acc]
                  else
                    acc
                  end
                _ -> acc
              end
            _ -> acc
          end
        end)
      _ -> []
    end

    resumen_total = Enum.reduce(balances_sorteos, %{recolectado: 0.0, pagado: 0.0, balance: 0.0}, fn b, acc ->
      %{
        recolectado: acc.recolectado + b.dinero_recolectado,
        pagado: acc.pagado + b.total_premios_pagados,
        balance: acc.balance + b.balance
      }
    end)

    registrar_bitacora("Admin", "Consultar balance general histórico", {:ok, "Generado"})
    {:reply, {:ok, %{sorteos: balances_sorteos, resumen: resumen_total}}, estado}
  end

  @impl true
  def handle_call(:sorteos_disponibles, _from, estado) do
    sorteos = listar_todos_los_sorteos_json()
    disponibles = Enum.filter(sorteos, fn s -> s["estado"] != "finalizado" end)
    {:reply, {:ok, disponibles}, estado}
  end

  @impl true
  def handle_call({:numeros_disponibles, nombre_sorteo}, _from, estado) do
    case Servidor.Persistencia.cargar_sorteo(nombre_sorteo) do
      {:error, _} -> {:reply, {:error, "El sorteo no existe."}, estado}
      {:ok, sorteo} ->
        max_billetes = sorteo["cantidad_billetes"]
        fracciones_totales = sorteo["fracciones"]
        ventas = Map.get(sorteo, "billetes_vendidos", [])

        conteo_ventas = Enum.reduce(ventas, %{}, fn v, acc ->
          Map.update(acc, v["numero"], v["fracciones"], &(&1 + v["fracciones"]))
        end)

        resultado = Enum.reduce(1..max_billetes, %{completos: [], fracciones: []}, fn num, acc ->
          vendidas = Map.get(conteo_ventas, num, 0)
          disponibles = fracciones_totales - vendidas

          cond do
            vendidas == 0 -> 
              Map.update!(acc, :completos, fn lista -> [num | lista] end)
            disponibles > 0 -> 
              Map.update!(acc, :fracciones, fn lista -> [{num, disponibles} | lista] end)
            true -> 
              acc
          end
        end)

        resultado_ordenado = %{
          completos: Enum.reverse(resultado.completos),
          fracciones: Enum.reverse(resultado.fracciones)
        }

        {:reply, {:ok, resultado_ordenado}, estado}
    end
  end

  @impl true
  def handle_call({:balance_personal_jugador, documento}, _from, estado) do
    sorteos = listar_todos_los_sorteos_json()
    perfil_final = calcular_perfil_limpio(sorteos, documento)
    {:reply, {:ok, perfil_final}, estado}
  end

  @impl true
  def handle_call({:devolver_compra, documento, nombre_sorteo, numero}, _from, estado) do
    case Servidor.Persistencia.cargar_sorteo(nombre_sorteo) do
      {:error, _} -> {:reply, {:error, "El sorteo no existe."}, estado}
      {:ok, sorteo} ->
        if sorteo["estado"] == "finalizado" do
          registrar_bitacora("Jugador #{documento}", "Intento devolver compra de sorteo ya jugado: #{nombre_sorteo}", {:error, "Denegado"})
          {:reply, {:error, "No se puede devolver la compra. El sorteo ya fue ejecutado."}, estado}
        else
          ventas = Map.get(sorteo, "billetes_vendidos", [])
          tiene_boleto = Enum.any?(ventas, fn v -> v["documento"] == documento and v["numero"] == numero end)

          if not tiene_boleto do
            {:reply, {:error, "No tienes ninguna compra registrada con el número ##{numero} en este sorteo."}, estado}
          else
            nuevas_ventas = Enum.filter(ventas, fn v -> not (v["documento"] == documento and v["numero"] == numero) end)
            sorteo_actualizado = Map.put(sorteo, "billetes_vendidos", nuevas_ventas)
            
            Servidor.Persistencia.guardar(nombre_sorteo, sorteo_actualizado)
            registrar_bitacora("Jugador #{documento}", "Devolución exitosa del billete ##{numero} de #{nombre_sorteo}", {:ok, "OK"})
            
            {:reply, {:ok, "Tu compra del billete ##{numero} ha sido devuelta y reembolsada con éxito."}, estado}
          end
        end
    end
  end

  @impl true
  def handle_call(:listar_premios_agrupados, _from, estado) do
    ruta_data = Path.join([File.cwd!(), "..", "..", "data"]) |> Path.expand()
    
    sorteos_con_premios = case File.ls(ruta_data) do
      {:ok, archivos} ->
        archivos
        |> Enum.filter(fn f -> String.end_with?(f, ".json") and not String.starts_with?(f, "jugador_") end)
        |> Enum.reduce([], fn archivo, acc ->
          path_completo = Path.join(ruta_data, archivo)
          case File.read(path_completo) do
            {:ok, contenido} ->
              case Jason.decode(contenido) do
                {:ok, json} ->
                  if Map.has_key?(json, "premios") and Map.has_key?(json, "fecha") do
                    [%{
                      "nombre" => json["nombre"],
                      "fecha" => json["fecha"],
                      "estado" => json["estado"],
                      "premios" => json["premios"]
                    } | acc]
                  else
                    acc
                  end
                _ -> acc
              end
            _ -> acc
          end
        end)
      _ -> []
    end

    sorteos_ordenados = Enum.sort_by(sorteos_con_premios, fn s -> s["fecha"] end)

    registrar_bitacora("Cliente", "Consultar listado global de premios", {:ok, "Generado"})
    {:reply, {:ok, sorteos_ordenados}, estado}
  end

  @impl true
  def handle_call({:solicitud, modulo_cliente, accion}, _from, estado) do
    resultado = procesar_accion(accion)
    registrar_bitacora(modulo_cliente, accion, resultado)
    {:reply, resultado, estado}
  end

  # ====================================================================
  # FUNCIONES PRIVADAS (Auxiliares lógicas)
  # ====================================================================

  defp procesar_accion(accion) do
    {:ok, "Recibí tu solicitud de: #{accion}"}
  end

  defp registrar_bitacora(cliente, solicitud, resultado_tupla) do
    ahora = NaiveDateTime.local_now()
    fecha_hora = NaiveDateTime.to_string(ahora) |> String.slice(0..18)

    resultado_str = case resultado_tupla do
      {:ok, _} -> "OK"
      {:error, _} -> "NEGADO"
      _ -> "DESCONOCIDO"
    end

    linea_log = "[#{fecha_hora}] - Solicitud: #{solicitud} (Por: #{cliente}) - Resultado: #{resultado_str}"

    IO.puts(IO.ANSI.cyan() <> "📝 LOG: " <> linea_log <> IO.ANSI.reset())

    ruta_bitacora = Path.join([File.cwd!(), "..", "..", "data", "bitacora.txt"]) |> Path.expand()
    File.write!(ruta_bitacora, linea_log <> "\n", [:append])
  end

  defp calcular_metricas_sorteo(sorteo) do
    ventas = Map.get(sorteo, "billetes_vendidos", [])
    fracciones_totales = sorteo["fracciones"]
    valor_billete = sorteo["valor"]
    precio_fraccion = valor_billete / fracciones_totales

    dinero_recolectado = Enum.reduce(ventas, 0.0, fn v, acc -> acc + (v["fracciones"] * precio_fraccion) end)

    premios_detalles = Enum.map(sorteo["premios"], fn p ->
      resultado_p = Enum.find(sorteo["resultados"] || [], fn r -> r["premio_nombre"] == p["nombre"] end)
      num_ganador = (resultado_p || %{})["numero_ganador"]

      ventas_ganadoras = Enum.filter(ventas, fn v -> v["numero"] == num_ganador end)

      ganadores_nombres = Enum.map(ventas_ganadoras, fn vg ->
        nombre = case Servidor.Persistencia.cargar_jugador(vg["documento"]) do
          {:ok, j} -> j["nombre"]
          _ -> "Desconocido"
        end
        pago_por_fraccion = p["valor"] / fracciones_totales
        dinero_ganado = pago_por_fraccion * vg["fracciones"]

        %{nombre: nombre, documento: vg["documento"], fracciones: vg["fracciones"], dinero_entregado: dinero_ganado}
      end)

      total_pagado_este_premio = Enum.reduce(ganadores_nombres, 0.0, fn g, acc -> acc + g.dinero_entregado end)

      %{
        nombre_premio: p["nombre"],
        valor_base_premio: p["valor"],
        numero_ganador: num_ganador,
        total_pagado: total_pagado_este_premio,
        ganadores: ganadores_nombres
      }
    end)

    total_premios_pagados = Enum.reduce(premios_detalles, 0.0, fn p, acc -> acc + p.total_pagado end)
    balance_neto = dinero_recolectado - total_premios_pagados

    %{
      nombre: sorteo["nombre"],
      fecha: sorteo["fecha"],
      dinero_recolectado: dinero_recolectado,
      total_premios_pagados: total_premios_pagados,
      balance: balance_neto,
      premios: premios_detalles
    }
  end

  defp listar_todos_los_sorteos_json() do
    ruta_data = Path.join([File.cwd!(), "..", "..", "data"]) |> Path.expand()
    case File.ls(ruta_data) do
      {:ok, archivos} ->
        archivos
        |> Enum.filter(fn f -> String.end_with?(f, ".json") and not String.starts_with?(f, "jugador_") end)
        |> Enum.map(fn f -> 
          {:ok, cont} = File.read(Path.join(ruta_data, f))
          Jason.decode!(cont)
        end)
      _ -> []
    end
  end

  defp calcular_perfil_limpio(sorteos, documento) do
    Enum.reduce(sorteos, %{compras: [], gastado: 0.0, premios: 0.0}, fn s, acc ->
      nombre_s = s["nombre"]
      precio_f = s["valor"] / s["fracciones"]
      ventas = Map.get(s, "billetes_vendidos", [])

      mis_ventas = Enum.filter(ventas, fn v -> v["documento"] == documento end)
      gastado_aqui = Enum.reduce(mis_ventas, 0.0, fn v, a -> a + (v["fracciones"] * precio_f) end)

      premios_aqui = if s["estado"] == "finalizado" and Map.has_key?(s, "resultados") do
        Enum.reduce(s["resultados"], 0.0, fn res, a_p ->
          compra_g = Enum.find(mis_ventas, fn mv -> mv["numero"] == res["numero_ganador"] end)
          if compra_g do
            premio_meta = Enum.find(s["premios"], fn p -> p["nombre"] == res["premio_nombre"] end)
            val_fracc = premio_meta["valor"] / s["fracciones"]
            a_p + (compra_g["fracciones"] * val_fracc)
          else
            a_p
          end
        end)
      else
        0.0
      end

      compras_formateadas = Enum.map(mis_ventas, fn mv -> 
        "Sorteo: #{nombre_s} | Billete: ##{mv["numero"]} | Fracciones: #{mv["fracciones"]} (Estado: #{s["estado"]})"
      end)

      %{
        compras: acc.compras ++ compras_formateadas,
        gastado: acc.gastado + gastado_aqui,
        premios: acc.premios + premios_aqui
      }
    end)
  end
end