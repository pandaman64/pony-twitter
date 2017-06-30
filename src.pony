use "net/http"
use "net/ssl"
use "files"
use "lib:oauth"

// 0 -> OA_HMAC
// 1 -> OA_RSA
// 2 -> OA_PLAINTEXT
use @oauth_sign_url2[Pointer[U8] ref](
    url: Pointer[U8] tag,
    postargs: Pointer[Pointer[U8]] tag,
    method: I32,
    http_method: Pointer[U8] tag,
    c_key: Pointer[U8] tag,
    c_secret: Pointer[U8] tag,
    t_key: Pointer[U8] tag,
    t_secret: Pointer[U8] tag
)

primitive SSLContextBuilder
    fun get(auth: AmbientAuth): (SSLContext val | None) =>
        try
            let cert_file = FilePath(auth, "cacert.pem")
            let ctx = recover iso SSLContext end
            ctx.set_client_verify(true)
            ctx.set_authority(cert_file)
            recover ctx end
        end

actor Twitter
    let _c_key: String
    let _c_sec: String
    let _t_key: String
    let _t_sec: String

    let _api_root: String = "https://api.twitter.com/1.1"

    let _ssl_context: (SSLContext | None)

    let _auth: AmbientAuth
    let _out: StdStream

    new create(c_key: String, c_sec: String, t_key: String, t_sec: String, auth: AmbientAuth, out: StdStream) =>
        _c_key = c_key
        _c_sec = c_sec
        _t_key = t_key
        _t_sec = t_sec
        _ssl_context = SSLContextBuilder.get(auth)
        _auth = auth
        _out = out

    be statuses_update(status: String) =>
        let method = "POST"
        let url: String val = recover
            let url_cstring = @oauth_sign_url2(
                (_api_root + "/statuses/update.json?status=" + status).cstring(),
                Pointer[Pointer[U8]],
                0,
                method.cstring(),
                _c_key.cstring(),
                _c_sec.cstring(),
                _t_key.cstring(),
                _t_sec.cstring()
            )
            String.from_cstring(consume url_cstring)
        end

        try
            let client = HTTPClient(_auth, _ssl_context)
            let url' = URL.build(url)
            let handler = recover val this~create_handler(_out) end
            let request = Payload.request(method, url')
            request("User-Agent") = "Pony-Twitter"
            client(consume request, handler)
        end

    be stream_user() =>
        let method = "GET"
        let url: String val = recover
            let url_cstring = @oauth_sign_url2(
                "https://userstream.twitter.com/1.1/user.json".cstring(),
                Pointer[Pointer[U8]],
                0,
                method.cstring(),
                _c_key.cstring(),
                _c_sec.cstring(),
                _t_key.cstring(),
                _t_sec.cstring()
            )
            String.from_cstring(consume url_cstring)
        end

        try
            let client = HTTPClient(_auth, _ssl_context)
            let url' = URL.build(url)
            let handler = recover val this~create_handler(_out) end
            let request = Payload.request(method, url')
            request("User-Agent") = "Pony-Twitter"
            client(consume request, handler)
        end

    fun tag create_handler(out: StdStream, session: HTTPSession tag): HTTPHandler =>
        _HTTPHandler(out)


actor Main
    new create(env: Env) =>
        try
            let file = File(FilePath(env.root as AmbientAuth, "keys"))
            let c_key = recover val file.line() end
            let c_sec = recover val file.line() end
            let t_key = recover val file.line() end
            let t_sec = recover val file.line() end

            let twitter = Twitter(c_key, c_sec, t_key, t_sec, env.root as AmbientAuth, env.out)
            twitter.stream_user()
        end

   
class _HTTPHandler
    let _out: StdStream
    var _buffer: String ref

    new create(out: StdStream) =>
        _out = out
        _buffer = recover "".clone() end

    fun ref apply(payload: Payload val): Any tag =>
        _out.print(payload.status.string())
        _out.print(payload.method)
        match payload.transfer_mode
        | ChunkedTransfer =>
            try
                for b in payload.body().values() do
                    _out.print("hig")
                    _out.print(b)
                end
            end
        end
        _out.print("payload")
        object is Any end

    fun ref take_one_json(): (String | None) =>
        try
            let start_index = _buffer.find("{")
            var end_index = start_index
            var count: USize = 0
            while end_index.usize() < _buffer.size() do
                if _buffer(end_index.usize()) == '{' then
                    count = count + 1
                elseif _buffer(end_index.usize()) == '}' then
                    count = count - 1
                end
                end_index = end_index + 1

                if count == 0 then
                    let json = _buffer.substring(start_index, end_index)
                    _buffer.trim_in_place(end_index.usize())
                    consume json
                end
            end
        end
        
    fun ref chunk(data: (String val | Array[U8 val] val)) =>
        _buffer.append(data)
        
        while true do
            match take_one_json()
            | let json: String => _out.print(consume json)
            | None => break
            end
        end

    fun ref finished() =>
        _out.print("finish!")

    fun ref cancelled() =>
        _out.print("cancell!")

    fun ref throttled() =>
        _out.print("throttle!")

    fun ref unthrottled() =>
        _out.print("unthrottle!")

    fun ref need_body() =>
        _out.print("need body!")

