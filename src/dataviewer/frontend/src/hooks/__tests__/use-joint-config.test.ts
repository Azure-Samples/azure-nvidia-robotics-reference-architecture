import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { _resetCsrfToken } from '@/lib/api-client'

const mockFetch = vi.fn()

function jsonResponse(data: unknown, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status === 200 ? 'OK' : 'Error',
    json: () => Promise.resolve(data),
  }
}

function mockMutationFetch(apiResponse: ReturnType<typeof jsonResponse>) {
  mockFetch
    .mockResolvedValueOnce(jsonResponse({ csrf_token: 'test-csrf-token' }))
    .mockResolvedValueOnce(apiResponse)
}

beforeEach(() => {
  mockFetch.mockReset()
  _resetCsrfToken()
  vi.stubGlobal('fetch', mockFetch)
})

afterEach(() => {
  vi.restoreAllMocks()
})

describe('joint config API functions', () => {
  it('saveJointConfig sends X-CSRF-Token header', async () => {
    const { saveJointConfigApi } = await import('@/hooks/use-joint-config')
    const responseData = {
      dataset_id: 'ds-1',
      labels: { '0': 'X' },
      groups: [{ id: 'g1', label: 'Group', indices: [0] }],
    }
    mockMutationFetch(jsonResponse(responseData))

    await saveJointConfigApi('ds-1', {
      datasetId: 'ds-1',
      labels: { '0': 'X' },
      groups: [{ id: 'g1', label: 'Group', indices: [0] }],
    })

    const putCall = mockFetch.mock.calls[1]
    expect(putCall[0]).toBe('/api/datasets/ds-1/joint-config')
    expect(putCall[1].headers).toHaveProperty('X-CSRF-Token', 'test-csrf-token')
  })

  it('saveJointConfigDefaults sends X-CSRF-Token header', async () => {
    const { saveJointConfigDefaultsApi } = await import('@/hooks/use-joint-config')
    const responseData = {
      dataset_id: '_defaults',
      labels: { '0': 'X' },
      groups: [{ id: 'g1', label: 'Group', indices: [0] }],
    }
    mockMutationFetch(jsonResponse(responseData))

    await saveJointConfigDefaultsApi({
      datasetId: '_defaults',
      labels: { '0': 'X' },
      groups: [{ id: 'g1', label: 'Group', indices: [0] }],
    })

    const putCall = mockFetch.mock.calls[1]
    expect(putCall[0]).toBe('/api/joint-config/defaults')
    expect(putCall[1].headers).toHaveProperty('X-CSRF-Token', 'test-csrf-token')
  })
})
