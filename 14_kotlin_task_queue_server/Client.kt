// Клиент сервера очереди задач.
// Два режима:
//   интерактивный — команды вводятся с клавиатуры и отправляются серверу;
//   --worker      — автоматический исполнитель: ждёт задачу, «выполняет» её и отчитывается.

import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.Socket

// Ответ сервера заканчивается строкой, начинающейся с одного из этих слов;
// строки, начинающиеся с пробела, — содержимое многострочного ответа.
val FINAL = listOf("OK", "ERR", "TASK", "EMPTY", "BYE")

fun readResponse(input: BufferedReader): List<String> {
    val lines = mutableListOf<String>()
    while (true) {
        val line = input.readLine() ?: break
        lines += line
        if (FINAL.any { line.startsWith(it) }) break
    }
    return lines
}

fun main(args: Array<String>) {
    val host = args.getOrNull(0) ?: "localhost"
    val port = args.getOrNull(1)?.toIntOrNull() ?: 7000
    val workerMode = args.contains("--worker")

    Socket(host, port).use { socket ->
        val out = PrintWriter(socket.getOutputStream().bufferedWriter(Charsets.UTF_8), true)
        val input = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
        println(readResponse(input).joinToString("\n"))   // приветствие

        fun request(cmd: String): List<String> {
            out.println(cmd)
            return readResponse(input)
        }

        if (workerMode) {
            println("Режим исполнителя: жду задачи (Ctrl+C — выход)")
            while (true) {
                val reply = request("WAIT").last()
                if (!reply.startsWith("TASK")) { println("Задач нет, жду дальше..."); continue }
                val (_, id, prio, text) = reply.split(" ", limit = 4)
                println("Взял задачу #$id (приоритет $prio): $text")
                Thread.sleep(1000L + 300L * text.length % 3000)   // имитация работы
                println(request("DONE $id").last())
            }
        } else {
            println("Введите команду (HELP — список, QUIT — выход):")
            while (true) {
                print("> ")
                val line = readLine() ?: break
                if (line.isBlank()) continue
                val reply = request(line.trim())
                println(reply.joinToString("\n"))
                if (reply.lastOrNull()?.startsWith("BYE") != false) break
            }
        }
    }
}
