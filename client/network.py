try:
    import usocket as socket
except ImportError:  # pragma: no cover - desktop fallback
    import socket

try:
    import uselect as select
except ImportError:  # pragma: no cover - desktop fallback
    import select

import config
import protocol
import assets


class SessionConnection:
    def __init__(self, tcp_sock, udp_sock, server_hello, server_ip):
        self.tcp_sock = tcp_sock
        self.udp_sock = udp_sock
        self.server_hello = server_hello
        self.server_ip = server_ip

    def send_input(self, snapshot):
        self.tcp_sock.sendall(protocol.encode_input_snapshot(snapshot))

    def recv_frame(self, timeout_ms=0):
        if hasattr(select, "poll"):
            poller = select.poll()
            poller.register(self.udp_sock, select.POLLIN)
            ready = poller.poll(timeout_ms)
            if not ready:
                return None
        else:
            ready = select.select([self.udp_sock], [], [], timeout_ms / 1000.0)[0]
            if not ready:
                return None

        payload, _ = self.udp_sock.recvfrom(8192)
        return protocol.decode_frame_state(payload)

    def close(self):
        try:
            self.tcp_sock.close()
        finally:
            self.udp_sock.close()


def open_session(session_info, status_cb=None):
    udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    udp_sock.bind(("", config.CLIENT_UDP_PORT))

    tcp_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp_sock.settimeout(config.TCP_CONNECT_TIMEOUT_S)
    tcp_sock.connect((session_info["address"], session_info["tcp_port"]))

    client_uuid = config.load_client_uuid()
    tcp_sock.sendall(protocol.encode_client_hello(client_uuid, config.CLIENT_UDP_PORT))

    packet_type, payload = protocol.recv_packet(tcp_sock)
    if packet_type != protocol.PACKET_SERVER_HELLO:
        raise RuntimeError("expected ServerHello packet")

    server_hello = protocol.decode_server_hello(payload)
    config.save_client_uuid(server_hello["client_uuid"])
    assets.sync_from_control_socket(tcp_sock, status_cb=status_cb)
    tcp_sock.settimeout(None)
    return SessionConnection(tcp_sock, udp_sock, server_hello, session_info["address"])
