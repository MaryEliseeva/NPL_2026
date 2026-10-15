# Параллельная обработка заказов несколькими процессами.
# Диспетчер хранит очередь заказов; каждый обработчик (отдельный процесс BEAM)
# сам просит следующий заказ, когда освободился, — так быстрые обработчики
# берут больше работы. Результаты возвращаются главному процессу сообщениями.

defmodule Orders do
  @discount_qty 10          # от 10 штук — скидка 10 %
  @discount_sum 50_000      # от 50 000 — дополнительная скидка 5 %
  @free_delivery 30_000
  @delivery 500

  def load(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Stream.drop(1)   # заголовок
    |> Enum.map(fn line ->
      [id, client, product, qty, price] = String.split(line, ";")
      %{id: String.to_integer(id), client: client, product: product,
        qty: String.to_integer(qty), price: String.to_integer(price)}
    end)
  end

  # Бизнес-логика обработки одного заказа.
  def process(%{qty: qty, price: price} = o) when qty <= 0 or price <= 0 do
    Map.merge(o, %{status: :rejected, reason: "некорректные количество или цена", total: 0})
  end

  def process(o) do
    subtotal = o.qty * o.price
    d1 = if o.qty >= @discount_qty, do: 0.10, else: 0.0
    d2 = if subtotal >= @discount_sum, do: 0.05, else: 0.0
    discounted = round(subtotal * (1 - d1 - d2))
    delivery = if discounted >= @free_delivery, do: 0, else: @delivery
    # имитация долгой работы (проверка склада, оплата и т.п.)
    Process.sleep(100 + :rand.uniform(300))
    Map.merge(o, %{status: :ok, subtotal: subtotal, discount: round((d1 + d2) * 100),
                   delivery: delivery, total: discounted + delivery})
  end

  # ---------- процессы ----------

  def dispatcher(queue, collector) do
    receive do
      {:ready, worker} ->
        case queue do
          [order | rest] ->
            send(worker, {:order, order})
            dispatcher(rest, collector)
          [] ->
            send(worker, :stop)
            dispatcher([], collector)
        end
    end
  end

  def worker(id, dispatcher, collector) do
    send(dispatcher, {:ready, self()})
    receive do
      {:order, order} ->
        t0 = System.monotonic_time(:millisecond)
        result = process(order)
        ms = System.monotonic_time(:millisecond) - t0
        send(collector, {:done, id, result, ms})
        worker(id, dispatcher, collector)
      :stop ->
        send(collector, {:worker_finished, id})
    end
  end

  def run(path, n_workers) do
    orders = load(path)
    IO.puts("Заказов: #{length(orders)}, обработчиков: #{n_workers}\n")
    me = self()
    t0 = System.monotonic_time(:millisecond)

    disp = spawn(fn -> dispatcher(orders, me) end)
    for id <- 1..n_workers, do: spawn(fn -> worker(id, disp, me) end)

    {results, busy} = collect(n_workers, [], %{})
    wall = System.monotonic_time(:millisecond) - t0
    Process.exit(disp, :normal)
    report(Enum.sort_by(results, & &1.id), busy, wall)
  end

  defp collect(0, results, busy), do: {results, busy}

  defp collect(active, results, busy) do
    receive do
      {:done, wid, r, ms} ->
        status = if r.status == :ok, do: "#{r.total} руб.", else: "ОТКЛОНЁН (#{r.reason})"
        IO.puts("  [обработчик #{wid}] заказ ##{r.id} (#{r.client}): #{status}, #{ms} мс")
        collect(active, [r | results], Map.update(busy, wid, {1, ms}, fn {c, t} -> {c + 1, t + ms} end))
      {:worker_finished, _wid} ->
        collect(active - 1, results, busy)
    end
  end

  defp report(results, busy, wall) do
    IO.puts("\n#{pad("№", 4)}#{pad("Клиент", 12)}#{pad("Товар", 16)}#{pad("Кол", 5)}#{pad("Скидка", 8)}Итого")
    for r <- results do
      tail = if r.status == :ok, do: "#{pad("#{r.discount}%", 8)}#{r.total}", else: "отклонён"
      IO.puts("#{pad(r.id, 4)}#{pad(r.client, 12)}#{pad(r.product, 16)}#{pad(r.qty, 5)}#{tail}")
    end

    ok = Enum.filter(results, &(&1.status == :ok))
    IO.puts("\nВыручка: #{Enum.sum(Enum.map(ok, & &1.total))} руб., " <>
            "отклонено: #{length(results) - length(ok)}")
    IO.puts("По клиентам:")
    ok
    |> Enum.group_by(& &1.client, & &1.total)
    |> Enum.sort()
    |> Enum.each(fn {c, ts} -> IO.puts("  #{pad(c, 12)}#{Enum.sum(ts)}") end)

    sequential = busy |> Map.values() |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    per_worker = busy |> Enum.sort() |> Enum.map(fn {w, {c, _}} -> "##{w}: #{c}" end)
    IO.puts("\nЗаказов на обработчик: " <> Enum.join(per_worker, ", "))
    IO.puts("Время работы: #{wall} мс (последовательно заняло бы ~#{sequential} мс)")
  end

  defp pad(v, n), do: String.pad_trailing(to_string(v), n)
end

[path | rest] = if System.argv() == [], do: ["orders.csv"], else: System.argv()
workers = case rest do
  [n | _] -> String.to_integer(n)
  [] -> 4
end
Orders.run(path, workers)
