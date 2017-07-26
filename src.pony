use "net/http"
use "net/ssl"
use "files"
use "json"
use "debug"
use "term"
use "promises"
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
            let cert_file = FilePath(auth, "cacert.pem")?
            let ctx = recover iso SSLContext end
            ctx.set_client_verify(true)
            ctx.set_authority(cert_file)?
            recover ctx end
        end

interface JsonConsumer
    fun apply(json: JsonDoc val)

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

    fun create_api_url(api_url: String, method: String): String =>
        recover
            let url_cstring = @oauth_sign_url2(
                api_url.cstring(),
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

    be request_api(api_url: String, method: String) =>
        let url = create_api_url(api_url, method)
        try
            let client = HTTPClient(_auth, _ssl_context)
            let url' = URL.build(url)?
            let handler = recover val this~create_handler() end
            let request = Payload.request(method, url')
            request("User-Agent") = "Pony-Twitter"
            client(consume request, handler)?
        end

    be statuses_update(status: String) =>
        request_api(_api_root + "/statuses/update.json?status=" + status, "GET")

    be stream_user() =>
        request_api("https://userstream.twitter.com/1.1/user.json", "POST")

    fun tag create_handler(session: HTTPSession tag): HTTPHandler =>
        _HTTPHandler(this~print_tweet())

    be print_tweet(json: JsonDoc val) =>
        try
            let tweet = json.data as JsonObject val
            let user = tweet.data("user")? as JsonObject val
            let user_name = user.data("name")? as String
            let screen_name = user.data("screen_name")? as String
            let created_at = tweet.data("created_at")? as String
            let text = tweet.data("text")? as String
            _out.write(user_name)
            _out.write("@")
            _out.write(screen_name)
            _out.write("\t\t")
            _out.print(created_at)
            _out.print(text)
        else
            Debug.out(json.string())
        end

actor Main
    new create(env: Env) =>
        try
            let file = File(FilePath(env.root as AmbientAuth, "keys")?)
            let c_key = recover val file.line()? end
            let c_sec = recover val file.line()? end
            let t_key = recover val file.line()? end
            let t_sec = recover val file.line()? end

            let twitter = Twitter(c_key, c_sec, t_key, t_sec, env.root as AmbientAuth, env.out)
            twitter.stream_user()

	    
            let notify = object iso
                fun ref apply(line: String, prompt: Promise[String]) =>
                    prompt(line)
                fun ref tab(line: String): Seq[String] box => Array[String]
            end
            let terminal = ANSITerm(Readline(consume notify, env.out), env.input)

            env.input(object iso
                fun ref apply(bytes: Array[U8] iso) =>
                    terminal.apply(consume bytes)
                fun ref dispose() =>
                    terminal.dispose()
            end)
        end
   
class _HTTPHandler
    var _buffer: String ref
    var _consumer: JsonConsumer

    new create(consumer: JsonConsumer) =>
        _buffer = String
        _consumer = consumer

    fun ref apply(payload: Payload val): Any tag =>
        Debug.out(payload.status.string())
        Debug.out(payload.method)
        match payload.transfer_mode
        | ChunkedTransfer =>
            try
                for b in payload.body()?.values() do
                    match b
                    | let b': String => Debug.out(b')
                    | let b': Array[U8] val => Debug.out(String.from_array(b'))
                    end
                end
            end
        end
        Debug.out("payload")
        object is Any end

    fun ref take_one_json(): (String | None) =>
        try
            let start_index = _buffer.find("{")?
            var end_index = start_index
            var count: USize = 0
            while end_index.usize() < _buffer.size() do
                if _buffer(end_index.usize())? == '{' then
                    count = count + 1
                elseif _buffer(end_index.usize())? == '}' then
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
            | let j: String =>
                try
                    let json = JsonDoc
                    json.parse(j)?
                    _consumer(consume json)
                else
                    Debug.out("parse failed")
                end
            | None => break
            end
        end

    fun ref finished() =>
        Debug.out("finish!")

    fun ref cancelled() =>
        Debug.out("cancell!")

    fun ref throttled() =>
        Debug.out("throttle!")

    fun ref unthrottled() =>
        Debug.out("unthrottle!")

    fun ref need_body() =>
        Debug.out("need body!")

