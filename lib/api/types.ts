export type ApiErrorBody = {
  code?: string;
  message?: string;
  details?: unknown;
};

export type ApiEnvelope<T> = {
  success: boolean;
  result: T | null;
  error: ApiErrorBody | null;
  metadata?: {
    apiVersion?: string;
    recommendedAppVersion?: string;
    pagination?: ApiPagination;
  };
};

export type ApiPagination = {
  nextCursor?: string | null;
  limit?: number;
  hasMore?: boolean;
};

export class ApiError extends Error {
  status: number;
  code?: string;
  details?: unknown;

  constructor(
    message: string,
    status: number,
    code?: string,
    details?: unknown,
  ) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.details = details;
  }
}
