package main

import (
	"context"
	"encoding/json"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// EventEmitter defines the interface for emitting progress events to the frontend or shell.
type EventEmitter interface {
	Emit(event string, data any)
}

// wailsEmitter delivers events via the Wails desktop runtime.
type wailsEmitter struct {
	ctx context.Context
}

func (w *wailsEmitter) Emit(event string, data any) {
	if w.ctx != nil {
		runtime.EventsEmit(w.ctx, event, data)
	}
}

// stdioEmitter formats events as JSON-RPC 2.0 notifications and writes them to an output stream.
type stdioEmitter struct {
	writer *synchronizedWriter
}

func newStdioEmitter(w *synchronizedWriter) *stdioEmitter {
	return &stdioEmitter{writer: w}
}

func (s *stdioEmitter) Emit(event string, data any) {
	notif := jsonrpcNotification{
		JSONRPC: "2.0",
		Method:  event,
		Params:  data,
	}
	payload, err := json.Marshal(notif)
	if err != nil {
		return
	}
	_ = s.writer.WriteLine(payload)
}
