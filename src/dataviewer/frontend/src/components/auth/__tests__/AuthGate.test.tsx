import { render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { AuthGate } from '../AuthGate'

const mockLoginRedirect = vi.fn()

vi.mock('@azure/msal-react', () => ({
  AuthenticatedTemplate: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="authenticated">{children}</div>
  ),
  UnauthenticatedTemplate: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="unauthenticated">{children}</div>
  ),
  useMsal: () => ({
    instance: { loginRedirect: mockLoginRedirect },
    inProgress: 'none',
  }),
}))

vi.mock('@/lib/auth-config', () => ({
  loginRequest: { scopes: ['api://test-client-id/access_as_user'] },
}))

describe('AuthGate', () => {
  beforeEach(() => {
    mockLoginRedirect.mockClear()
  })

  it('renders children inside AuthenticatedTemplate', () => {
    render(
      <AuthGate>
        <div>Protected Content</div>
      </AuthGate>,
    )

    const authenticated = screen.getByTestId('authenticated')
    expect(authenticated).toHaveTextContent('Protected Content')
  })

  it('triggers loginRedirect when unauthenticated and interaction is idle', () => {
    render(
      <AuthGate>
        <div>Protected Content</div>
      </AuthGate>,
    )

    expect(mockLoginRedirect).toHaveBeenCalledWith({
      scopes: ['api://test-client-id/access_as_user'],
    })
  })
})
