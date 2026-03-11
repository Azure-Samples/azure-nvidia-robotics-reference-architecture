import { InteractionStatus } from '@azure/msal-browser'
import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from '@azure/msal-react'
import { useEffect } from 'react'

import { loginRequest } from '@/lib/auth-config'

export function AuthGate({ children }: { children: React.ReactNode }) {
  return (
    <>
      <AuthenticatedTemplate>{children}</AuthenticatedTemplate>
      <UnauthenticatedTemplate>
        <LoginRedirect />
      </UnauthenticatedTemplate>
    </>
  )
}

function LoginRedirect() {
  const { instance, inProgress } = useMsal()

  useEffect(() => {
    if (inProgress === InteractionStatus.None) {
      instance.loginRedirect(loginRequest)
    }
  }, [instance, inProgress])

  return null
}
