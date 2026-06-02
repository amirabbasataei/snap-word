package ws

import (
	"log/slog"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 4096
)

// Client is the bridge between one WebSocket connection and its game room.
type Client struct {
	room   *Room
	userID string
	conn   *websocket.Conn
	send   chan []byte
}

// NewClient constructs a Client. Call ReadPump and WritePump as goroutines afterwards.
func NewClient(room *Room, userID string, conn *websocket.Conn) *Client {
	return &Client{
		room:   room,
		userID: userID,
		conn:   conn,
		send:   make(chan []byte, 256),
	}
}

// ReadPump pumps messages from the WebSocket connection into the room.
// Must run in its own goroutine; closes the connection on return.
func (c *Client) ReadPump() {
	defer func() {
		c.room.leave(c)
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		return c.conn.SetReadDeadline(time.Now().Add(pongWait))
	})

	for {
		_, msg, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				slog.Warn("ws: unexpected close", "userID", c.userID, "error", err)
			}
			return
		}
		c.room.handleMessage(c, msg)
	}
}

// WritePump pumps messages from the send channel to the WebSocket connection,
// and keeps the connection alive with periodic pings.
// Must run in its own goroutine.
func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case msg, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// Room closed the channel.
				_ = c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				slog.Warn("ws: write error", "userID", c.userID, "error", err)
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
