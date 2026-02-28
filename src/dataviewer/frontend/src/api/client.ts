/**
 * HTTP API client for backend communication.
 */

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

interface RequestConfig extends RequestInit {
  params?: Record<string, string | number | boolean | undefined>;
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

    const response = await fetch(url, {
      ...fetchConfig,
      headers: {
        'Content-Type': 'application/json',
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
