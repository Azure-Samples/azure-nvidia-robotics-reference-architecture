/**
 * HTTP API client for backend communication.
 */

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

interface RequestConfig extends RequestInit {
  params?: Record<string, string | number | boolean | undefined>;
}

const MUTATION_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

/** Cached CSRF token fetched from the server. */
let _csrfToken: string | null = null;
/** In-flight CSRF token fetch promise to prevent duplicate requests. */
let _csrfTokenFetch: Promise<string> | null = null;

async function getCsrfToken(): Promise<string> {
  if (_csrfToken) return _csrfToken;
  if (!_csrfTokenFetch) {
    _csrfTokenFetch = fetch(`${API_BASE_URL}/api/csrf-token`)
      .then((response) => {
        if (!response.ok) {
          throw new Error(`Failed to fetch CSRF token: ${response.statusText}`);
        }
        return response.json();
      })
      .then((data) => {
        _csrfToken = data.csrf_token as string;
        _csrfTokenFetch = null;
        return _csrfToken;
      })
      .catch((err) => {
        _csrfTokenFetch = null;
        throw err;
      });
  }
  return _csrfTokenFetch;
}

/**
 * Generic API client with error handling.
 */
class ApiClient {
  private baseUrl: string;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
  }

  private buildUrl(path: string, params?: RequestConfig['params']): string {
    const url = new URL(path, this.baseUrl);
    if (params) {
      Object.entries(params).forEach(([key, value]) => {
        if (value !== undefined) {
          url.searchParams.append(key, String(value));
        }
      });
    }
    return url.toString();
  }

  private async request<T>(path: string, config: RequestConfig = {}): Promise<T> {
    const { params, ...fetchConfig } = config;
    const url = this.buildUrl(path, params);

    const method = (fetchConfig.method ?? 'GET').toUpperCase();
    const extraHeaders: Record<string, string> = {};

    if (MUTATION_METHODS.has(method)) {
      extraHeaders['X-CSRF-Token'] = await getCsrfToken();
    }

    const response = await fetch(url, {
      ...fetchConfig,
      headers: {
        'Content-Type': 'application/json',
        ...extraHeaders,
        ...fetchConfig.headers,
      },
    });

    if (!response.ok) {
      const error = await response.json().catch(() => ({ detail: response.statusText }));
      throw new Error(error.detail || `HTTP ${response.status}`);
    }

    return response.json();
  }

  async get<T>(path: string, params?: RequestConfig['params']): Promise<T> {
    return this.request<T>(path, { method: 'GET', params });
  }

  async post<T>(path: string, data?: unknown): Promise<T> {
    return this.request<T>(path, {
      method: 'POST',
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async put<T>(path: string, data?: unknown): Promise<T> {
    return this.request<T>(path, {
      method: 'PUT',
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async delete<T>(path: string): Promise<T> {
    return this.request<T>(path, { method: 'DELETE' });
  }
}

export const apiClient = new ApiClient(API_BASE_URL);
