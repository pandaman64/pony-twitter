use "net/http"
use "term"
use "promises"

class Notify
    fun ref apply(line: String, prompt: Promise[String]) =>
        prompt(line)
    fun ref tab(line: String): Seq[String] box => Array[String]

actor Main
    new create(env: Env) =>
        try
            let client = HTTPClient(env.root as AmbientAuth, None)
            let url = URL.build("")?
            let handler = object
                fun tag apply(session: HTTPSession tag): HTTPHandler =>
                    object ref is HTTPHandler end
            end
            let request = Payload.request("", url)
            client(consume request, handler)?
        end

        let readline = Readline(Notify, env.out)
        // compiler will not crash if you comment this line
        let terminal = ANSITerm(consume readline, env.input)

