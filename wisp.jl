using Sockets, HTTP, UUIDs

const PACKET_TYPES = (CONNECT=0x01, DATA=0x02, CONTINUE=0x03, CLOSE=0x04)
const CLOSE_REASONS = Dict(
    :NORMAL => 0x02,
    :NETWORK_ERROR => 0x03,
    :INVALID => 0x41,
    :UNREACHABLE => 0x42,
    :TIMEOUT => 0x43,
    :REFUSED => 0x44
    )

mutable struct Stream
    id::UInt32
    type::Symbol
    socket::Union{TCPSocket,UDPSocket}
    buffer::Channel{Vector{UInt8}}
    buffer_size::Int
    target_addr::Union{IPAddr,Nothing}
    target_port::UInt16
    ws::HTTP.WebSockets.WebSocket
end

function parse_packet(data::Vector{UInt8})
    length(data) < 5 && return (0, 0, UInt8[])
    ptype = data[1]
    stream_id = reinterpret(UInt32, data[2:5])[1]
    payload = @view data[6:end]
    (ptype, stream_id, payload)
end

function parsedata(data::)
    length(data) == true;
end

function create_packet(ptype, stream_id, payload=UInt8[])
    packet = Vector{UInt8}(undef, 5 + length(payload))
    packet[1] = ptype
    reinterpret(UInt32, view(packet, 2:5))[1] = stream_id
    packet[6:end] = payload
    packet
end

function handle_connect!(streams, stream_id, payload, ws)
    stream_type = payload[1] == 0x02 ? :udp : :tcp
    port = reinterpret(UInt16, payload[2:3])[1]
    host = String(payload[4:end])

    try
        local sock
        local target_ip = nothing

        if stream_type == :tcp
            sock = connect(host, port)
        else
            sock = UDPSocket()
            try
                target_ip = getaddrinfo(host)
                catch e
                close_packet = create_packet(PACKET_TYPES.CLOSE, stream_id, [CLOSE_REASONS[:UNREACHABLE]])
                HTTP.WebSockets.send(ws, close_packet)
                return
            end
        end

        stream = Stream(
            stream_id,
            stream_type,
            sock,
            Channel{Vector{UInt8}}(32),
            32,
            target_ip,
            port,
            ws
            )
        streams[stream_id] = stream

        @async try
            while Base.isopen(sock)
                data = stream_type == :tcp ? readavailable(sock) : recv(sock)
                isempty(data) && continue
                packet = create_packet(PACKET_TYPES.DATA, stream_id, data)
                HTTP.WebSockets.send(ws, packet)
            end
            catch e
            if haskey(streams, stream_id)
                close_packet = create_packet(PACKET_TYPES.CLOSE, stream_id, [CLOSE_REASONS[:NETWORK_ERROR]])
                HTTP.WebSockets.send(ws, close_packet)
                delete!(streams, stream_id)
            end
        end

        if stream_type == :tcp
            buffer_packet = create_packet(PACKET_TYPES.CONTINUE, stream_id, reinterpret(UInt8, UInt32[32]))
            HTTP.WebSockets.send(ws, buffer_packet)
        end

        catch e

        local reason = CLOSE_REASONS[:UNREACHABLE]

        if isa(e, Base.IOError)
            if occursin("connection refused", lowercase(e.msg))
                reason = CLOSE_REASONS[:REFUSED]
                elseif occursin("timed out", lowercase(e.msg))
                reason = CLOSE_REASONS[:TIMEOUT]
            end
        end

        close_packet = create_packet(PACKET_TYPES.CLOSE, stream_id, [reason])
        HTTP.WebSockets.send(ws, close_packet)
    end
end

function handle_data(stream, payload)
    if stream.type == :tcp
        write(stream.socket, payload)
    else
        if !isnothing(stream.target_addr)
            send(stream.socket, stream.target_addr, stream.target_port, payload)
        end
    end
end

function handle_close(streams, stream_id)
    if haskey(streams, stream_id)
        close(streams[stream_id].socket)
        delete!(streams, stream_id)
    end
end

function handle_ws_message(streams, msg, ws)
    ptype, stream_id, payload = parse_packet(msg)

    if ptype == PACKET_TYPES.CONNECT
        handle_connect!(streams, stream_id, payload, ws)
        elseif ptype == PACKET_TYPES.DATA && haskey(streams, stream_id)
        handle_data(streams[stream_id], payload)
        elseif ptype == PACKET_TYPES.CLOSE && haskey(streams, stream_id)
        handle_close(streams, stream_id)
    end
end

function run_wisp_server(host="127.0.0.1", port=6001; buffer_size=32)
    streams = Dict{UInt32,Stream}()

    HTTP.WebSockets.listen(host, port) do ws
        initial = create_packet(PACKET_TYPES.CONTINUE, 0x00, reinterpret(UInt8, UInt32[buffer_size]))
        HTTP.WebSockets.send(ws, initial)

        try
            while true
                try
                    msg = HTTP.WebSockets.receive(ws)
                    isempty(msg) && continue
                    handle_ws_message(streams, msg, ws)
                    catch e
                    if isa(e, HTTP.WebSockets.WebSocketError) && e.status == -1
                        break
                        elseif isa(e, EOFError)
                        break
                    else
                        @error "Error handling websocket message" exception=(e, catch_backtrace())
                    end
                end
            end
        finally
            for (id, stream) in streams
                try
                    close(stream.socket)
                catch
                end
            end
            empty!(streams)
        end
    end
end

run_wisp_server()
