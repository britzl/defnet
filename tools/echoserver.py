# Example of simple echo server
# www.solusipse.net
# https://gist.github.com/solusipse/6419144
# Modifed by britzl (https://github.com/britzl)

import socket


def listen():
    connection = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    connection.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    connection.bind(('0.0.0.0', 5555))
    connection.listen(10)
    while True:
        print "Waiting for connection"
        current_connection, address = connection.accept()
        print "Client connection " + str(address)
        while True:
            data = current_connection.recv(2048)
            if data != "":
                current_connection.send(data)
                print data

            else:
                print "Client disconnected " + str(address)
                current_connection.shutdown(1)
                current_connection.close()
                break


if __name__ == "__main__":
    try:
        listen()
    except KeyboardInterrupt:
        pass
