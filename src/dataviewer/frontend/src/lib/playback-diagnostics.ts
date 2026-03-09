export const DIAGNOSTICS_STORAGE_KEY = 'dataviewer:diagnostics'
export const DIAGNOSTICS_EVENT_NAME = 'dataviewer:diagnostics'

const MAX_DIAGNOSTIC_EVENTS = 200

export interface PlaybackDiagnosticEvent {
  channel: string
  type: string
  data?: Record<string, unknown>
  timestamp: string
}

declare global {
  interface Window {
    __dataviewerDiagnostics__?: PlaybackDiagnosticEvent[]
  }
}

function splitChannels(raw: string | null | undefined) {
  return (raw ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean)
}

function getSearchValue(name: string) {
  if (typeof window === 'undefined') {
    return null
  }

  return new URLSearchParams(window.location.search).get(name)
}

function getStoredDiagnosticsValue() {
  if (typeof window === 'undefined') {
    return null
  }

  const storage = window.localStorage

  if (!storage || typeof storage.getItem !== 'function') {
    return null
  }

  return storage.getItem(DIAGNOSTICS_STORAGE_KEY)
}

function getConfiguredChannels() {
  const searchChannels = splitChannels(getSearchValue('diagnostics'))
  const storageChannels = splitChannels(getStoredDiagnosticsValue())
  const envChannels = splitChannels(import.meta.env.VITE_DATAVIEWER_DIAGNOSTICS)

  return new Set([...envChannels, ...storageChannels, ...searchChannels])
}

function getDiagnosticBuffer() {
  if (typeof window === 'undefined') {
    return []
  }

  window.__dataviewerDiagnostics__ ??= []

  return window.__dataviewerDiagnostics__
}

export function isDiagnosticsChannelEnabled(channel: string) {
  const channels = getConfiguredChannels()

  return channels.has('all') || channels.has(channel)
}

export function readDiagnosticEvents(channel: string) {
  return getDiagnosticBuffer().filter((event) => event.channel === channel)
}

export function clearDiagnosticEvents(channel?: string) {
  if (typeof window === 'undefined' || !window.__dataviewerDiagnostics__) {
    return
  }

  if (!channel) {
    window.__dataviewerDiagnostics__ = []
    return
  }

  window.__dataviewerDiagnostics__ = window.__dataviewerDiagnostics__.filter((event) => event.channel !== channel)
}

export function recordDiagnosticEvent(channel: string, type: string, data?: Record<string, unknown>) {
  if (!isDiagnosticsChannelEnabled(channel) || typeof window === 'undefined') {
    return
  }

  const events = getDiagnosticBuffer()

  events.push({
    channel,
    type,
    data,
    timestamp: new Date().toISOString(),
  })

  if (events.length > MAX_DIAGNOSTIC_EVENTS) {
    events.splice(0, events.length - MAX_DIAGNOSTIC_EVENTS)
  }

  window.dispatchEvent(new CustomEvent(DIAGNOSTICS_EVENT_NAME, { detail: { channel, type, data } }))
}
