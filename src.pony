use "net/http"
use "net/ssl"
use "files"

primitive SSLContextBuilder
    fun get(auth: AmbientAuth): (SSLContext val | None) =>
        try
            let cert_file = FilePath(auth, "cacert.pem")
            let ctx = recover iso SSLContext end
            ctx.set_client_verify(true)
            ctx.set_authority(cert_file)
            recover ctx end
        end

actor Main
    new create(env: Env) =>
        try
            let client = HTTPClient(env.root as AmbientAuth, SSLContextBuilder.get(env.root as AmbientAuth))
            let url = URL.build("https://www.ponylang.org/learn/")
            let handler = object val
                fun apply(session: HTTPSession tag): HTTPHandler =>
                    _HTTPHandler(env.out)
            end
            let request = Payload.request("GET", url)
            request("User-Agent") = "Pony"
            client(consume request, handler)
        end
   
class _HTTPHandler
    let _out: StdStream
    var _buffer: String ref

    new create(out: StdStream) =>
        _out = out
        _buffer = recover "".clone() end
    
    fun ref apply(payload: Payload val): Any tag => None
        
    fun ref chunk(data: (String val | Array[U8 val] val)) =>
        _out.print("chunk")
        _buffer.append(data)
        _buffer.trim_in_place(_buffer.size())

    fun ref finished() => None
    fun ref cancelled() => None
    fun ref throttled() => None
    fun ref unthrottled() => None
    fun ref need_body() => None

