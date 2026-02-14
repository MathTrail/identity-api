import { create } from 'zustand'
import { Session, Identity } from '@ory/client'
import { kratos } from '@/lib/kratos'

interface AuthState {
  session: Session | null
  identity: Identity | null
  loading: boolean
  initialized: boolean
  setSession: (session: Session | null) => void
  setLoading: (loading: boolean) => void
  initialize: () => Promise<void>
  logout: () => void
}

export const useAuthStore = create<AuthState>((set, get) => ({
  session: null,
  identity: null,
  loading: true,
  initialized: false,

  setSession: (session) => set({
    session,
    identity: session?.identity ?? null,
  }),

  setLoading: (loading) => set({ loading }),

  initialize: async () => {
    if (get().initialized) return
    try {
      const { data } = await kratos.toSession()
      set({
        session: data,
        identity: data.identity,
        loading: false,
        initialized: true,
      })
    } catch {
      set({ session: null, identity: null, loading: false, initialized: true })
    }
  },

  logout: () => set({ session: null, identity: null }),
}))
