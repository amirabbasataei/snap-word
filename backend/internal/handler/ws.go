package handler

import (
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"

	"wordchain/backend/internal/service"
	"wordchain/backend/internal/ws"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// Allow all origins in dev. TODO: restrict in production via config.CORSOrigins.
	CheckOrigin: func(r *http.Request) bool { return true },
}

// WSHandler upgrades HTTP connections to WebSocket game sessions.
type WSHandler struct {
	hub     *ws.Hub
	authSvc *service.AuthService
}

func NewWSHandler(hub *ws.Hub, authSvc *service.AuthService) *WSHandler {
	return &WSHandler{hub: hub, authSvc: authSvc}
}

// ServeWS handles GET /api/v1/ws/game/:roomID.
//
// Query parameters:
//   - token  (required) — JWT access token (WS cannot carry Authorization headers)
//   - mode   (optional) — "classic" (default) or "time_attack"; used only when the
//     room does not already exist
func (h *WSHandler) ServeWS(c *gin.Context) {
	roomID := c.Param("roomID")

	// Authenticate via query param because WebSocket handshakes cannot carry
	// custom headers in most browser / mobile environments.
	token := c.Query("token")
	if token == "" {
		respondError(c, http.StatusUnauthorized, "missing_token", "token query param required")
		return
	}
	userID, _, err := h.authSvc.ParseAccessToken(token)
	if err != nil {
		respondError(c, http.StatusUnauthorized, "invalid_token", "invalid or expired token")
		return
	}

	mode := c.DefaultQuery("mode", "classic")
	if mode != "classic" && mode != "time_attack" {
		respondError(c, http.StatusBadRequest, "invalid_mode", "mode must be classic or time_attack")
		return
	}

	room := h.hub.GetOrCreateRoom(roomID, mode)

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		slog.Error("ws: upgrade failed", "room", roomID, "userID", userID, "error", err)
		return
	}

	client := ws.NewClient(room, userID, conn)

	if err := room.Join(client); err != nil {
		slog.Warn("ws: join rejected", "room", roomID, "userID", userID, "reason", err)
		_ = conn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseNormalClosure, err.Error()))
		conn.Close()
		return
	}

	slog.Info("ws: client connected", "room", roomID, "userID", userID)
	go client.WritePump()
	client.ReadPump() // blocks until disconnect; ReadPump calls room.leave on exit
}
