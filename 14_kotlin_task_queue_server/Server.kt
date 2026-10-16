// Сервер очереди задач.
// Клиенты-«постановщики» кладут задачи с приоритетом, клиенты-«исполнители» забирают
// их, выполняют и отчитываются. Каждый клиент обслуживается в отдельном потоке;
// общая очередь — потокобезопасная PriorityBlockingQueue.

import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.ServerSocket
import java.net.Socket
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.PriorityBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

enum class Status { QUEUED, IN_PROGRESS, DONE }

class Task(val id: Int, val priority: Int, val text: String) {
    @Volatile var status = Status.QUEUED
    @Volatile var worker: String? = null
}

object Queue {
    private val nextId = AtomicInteger(1)
    val all = ConcurrentHashMap<Int, Task>()
    // Сначала больший приоритет, при равном — более ранняя задача (FIFO).
    private val waiting = PriorityBlockingQueue<Task>(16,
        compareByDescending<Task> { it.priority }.thenBy { it.id })

    fun push(priority: Int, text: String): Task {
        val t = Task(nextId.getAndIncrement(), priority, text)
        all[t.id] = t
        waiting.put(t)
        return t
    }

    fun requeue(t: Task) {
        t.status = Status.QUEUED
        t.worker = null
        waiting.put(t)
    }

    /** Взять задачу: timeoutSec = 0 — не ждать, иначе ждать появления задачи. */
    fun take(worker: String, timeoutSec: Long): Task? {
        val t = if (timeoutSec == 0L) waiting.poll() else waiting.poll(timeoutSec, TimeUnit.SECONDS)
        if (t != null) {
            t.status = Status.IN_PROGRESS
            t.worker = worker
        }
        return t
    }

    fun queued() = waiting.toTypedArray().sortedWith(compareByDescending<Task> { it.priority }.thenBy { it.id })
    fun count(s: Status) = all.values.count { it.status == s }
}

fun log(msg: String) = println("[${LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss"))}] $msg")

class ClientHandler(private val socket: Socket) {
    private val name = "${socket.inetAddress.hostAddress}:${socket.port}"
    private val out = PrintWriter(socket.getOutputStream().bufferedWriter(Charsets.UTF_8), true)
    private val input = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
    private val taken = mutableSetOf<Int>()   // задачи, которые этот клиент взял и не завершил

    fun run() {
        log("+ подключился $name")
        out.println("OK очередь задач, HELP — список команд")
        try {
            while (true) {
                val line = input.readLine() ?: break
                if (line.isBlank()) continue
                if (!handle(line.trim())) break
            }
        } catch (e: Exception) {
            log("ошибка у $name: ${e.message}")
        } finally {
            // Если клиент отключился посреди работы — его задачи возвращаются в очередь.
            for (id in taken) Queue.all[id]?.let {
                Queue.requeue(it)
                log("задача #$id возвращена в очередь (исполнитель $name отключился)")
            }
            socket.close()
            log("- отключился $name")
        }
    }

    private fun handle(line: String): Boolean {
        val parts = line.split(" ", limit = 3)
        val cmd = parts[0]
        fun isCmd(name: String) = cmd.equals(name, ignoreCase = true)
        when {
            isCmd("PUSH") -> {
                val prio = parts.getOrNull(1)?.toIntOrNull()
                val text = parts.getOrNull(2)
                if (prio == null || prio !in 1..10 || text.isNullOrBlank()) {
                    out.println("ERR формат: PUSH <приоритет 1-10> <описание>")
                } else {
                    val t = Queue.push(prio, text)
                    log("$name поставил задачу #${t.id} (приоритет $prio): $text")
                    out.println("OK задача #${t.id} в очереди")
                }
            }
            isCmd("TAKE") || isCmd("WAIT") -> {
                // TAKE — сразу, WAIT — ждать до 30 секунд, пока задача не появится
                val t = Queue.take(name, if (isCmd("WAIT")) 30L else 0L)
                if (t == null) out.println("EMPTY очередь пуста")
                else {
                    taken += t.id
                    log("$name взял задачу #${t.id}")
                    out.println("TASK ${t.id} ${t.priority} ${t.text}")
                }
            }
            isCmd("DONE") || isCmd("FAIL") -> {
                val id = parts.getOrNull(1)?.toIntOrNull()
                val t = id?.let { Queue.all[it] }
                when {
                    t == null -> out.println("ERR нет такой задачи")
                    t.id !in taken -> out.println("ERR задача #${t.id} не выполняется этим клиентом")
                    isCmd("DONE") -> {
                        t.status = Status.DONE
                        taken -= t.id
                        log("$name выполнил задачу #${t.id}")
                        out.println("OK задача #${t.id} выполнена")
                    }
                    else -> {
                        taken -= t.id
                        Queue.requeue(t)
                        log("$name вернул задачу #${t.id} в очередь")
                        out.println("OK задача #${t.id} возвращена в очередь")
                    }
                }
            }
            isCmd("LIST") -> {
                val q = Queue.queued()
                for (t in q) out.println("  #${t.id} [приоритет ${t.priority}] ${t.text}")
                out.println("OK в очереди ${q.size}")
            }
            isCmd("STATUS") -> out.println(
                "OK в очереди ${Queue.count(Status.QUEUED)}, в работе ${Queue.count(Status.IN_PROGRESS)}, " +
                "выполнено ${Queue.count(Status.DONE)}")
            isCmd("HELP") -> {
                out.println("  PUSH <1-10> <описание> — поставить задачу")
                out.println("  TAKE — взять задачу, WAIT — ждать задачу до 30 с")
                out.println("  DONE <id> — задача выполнена, FAIL <id> — вернуть в очередь")
                out.println("  LIST — очередь, STATUS — счётчики, QUIT — выход")
                out.println("OK")
            }
            isCmd("QUIT") -> { out.println("BYE"); return false }
            else -> out.println("ERR неизвестная команда, HELP — список команд")
        }
        return true
    }
}

fun main(args: Array<String>) {
    val port = args.firstOrNull()?.toIntOrNull() ?: 7000
    val server = ServerSocket(port)
    log("Сервер очереди задач слушает порт $port")
    while (true) {
        val socket = server.accept()
        thread(isDaemon = true) { ClientHandler(socket).run() }
    }
}
