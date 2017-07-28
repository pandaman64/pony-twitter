use "net/http"
use "term"
use "promises"

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

        let notify = object iso
            fun ref apply(line: String, prompt: Promise[String]) =>
                prompt(line)
            fun ref tab(line: String): Seq[String] box => Array[String]
        end
        let terminal = ANSITerm(Readline(consume notify, env.out), env.input)

