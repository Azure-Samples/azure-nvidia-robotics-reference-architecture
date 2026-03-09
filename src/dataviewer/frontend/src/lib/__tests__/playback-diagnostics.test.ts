import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import {
  clearDiagnosticEvents,
  DIAGNOSTICS_STORAGE_KEY,
  isDiagnosticsChannelEnabled,
  readDiagnosticEvents,
  recordDiagnosticEvent,
} from '../playback-diagnostics'

describe('playback diagnostics', () => {
  const originalLocation = window.location
  const storage = new Map<string, string>()

  beforeEach(() => {
    Object.defineProperty(window, 'localStorage', {
      configurable: true,
      value: {
        clear: () => storage.clear(),
        getItem: (key: string) => storage.get(key) ?? null,
        removeItem: (key: string) => storage.delete(key),
        setItem: (key: string, value: string) => storage.set(key, value),
      },
    })
    localStorage.clear()
    clearDiagnosticEvents('playback')
  })

  afterEach(() => {
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: originalLocation,
    })
  })

  it('enables a channel from local storage without affecting default behavior', () => {
    expect(isDiagnosticsChannelEnabled('playback')).toBe(false)

    localStorage.setItem(DIAGNOSTICS_STORAGE_KEY, 'playback')

    expect(isDiagnosticsChannelEnabled('playback')).toBe(true)
  })

  it('enables a channel from the diagnostics query string', () => {
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: {
        ...originalLocation,
        search: '?diagnostics=playback',
      },
    })

    expect(isDiagnosticsChannelEnabled('playback')).toBe(true)
  })

  it('records a bounded playback event stream only when the channel is enabled', () => {
    recordDiagnosticEvent('playback', 'selection-complete', { range: [10, 20] })

    expect(readDiagnosticEvents('playback')).toEqual([])

    localStorage.setItem(DIAGNOSTICS_STORAGE_KEY, 'playback')

    for (let index = 0; index < 205; index += 1) {
      recordDiagnosticEvent('playback', 'tick', { index })
    }

    const events = readDiagnosticEvents('playback')

    expect(events).toHaveLength(200)
    expect(events[0]?.data).toEqual({ index: 5 })
    expect(events[events.length - 1]?.data).toEqual({ index: 204 })
  })
})
