export type SessionUser = {
  id: string;
  avatarUrl: string | null;
  email: string;
  username?: string | null;
};

export type SessionResult = {
  user: SessionUser;
  emailVerified: boolean;
};

export type LoginResult = {
  user: {
    id: string;
    avatarUrl: string | null;
  };
};

export type LoginBody = {
  email: string;
  password: string;
};
