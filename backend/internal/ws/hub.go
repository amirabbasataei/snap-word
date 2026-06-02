package ws

import "sync"

// Hub manages all active game rooms and their lifecycles.
type Hub struct {
	mu    sync.RWMutex
	rooms map[string]*Room
	deps  RoomDeps
}

// NewHub creates a Hub with the given room dependencies.
func NewHub(deps RoomDeps) *Hub {
	return &Hub{
		rooms: make(map[string]*Room),
		deps:  deps,
	}
}

// GetOrCreateRoom returns the room for roomID, creating one with the given mode
// if it does not yet exist.
func (h *Hub) GetOrCreateRoom(roomID, mode string) *Room {
	h.mu.Lock()
	defer h.mu.Unlock()

	if r, ok := h.rooms[roomID]; ok {
		return r
	}
	r := newRoom(roomID, mode, h, h.deps)
	h.rooms[roomID] = r
	return r
}

// GetRoom returns the room for roomID and whether it existed.
func (h *Hub) GetRoom(roomID string) (*Room, bool) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	r, ok := h.rooms[roomID]
	return r, ok
}

// RemoveRoom deletes a finished room from the hub.
func (h *Hub) RemoveRoom(roomID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.rooms, roomID)
}
