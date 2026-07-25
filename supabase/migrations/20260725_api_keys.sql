-- API Keys table for managing multiple AI provider keys
-- Each user can have multiple API keys stored securely

CREATE TABLE IF NOT EXISTS api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  provider TEXT NOT NULL DEFAULT 'custom',
  base_url TEXT NOT NULL,
  model TEXT NOT NULL DEFAULT '',
  api_key TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Each user can have only one active key at a time
CREATE UNIQUE INDEX IF NOT EXISTS idx_api_keys_active_per_user 
ON api_keys(user_id) WHERE is_active = true;

-- Enable RLS
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;

-- Users can only see/delete their own keys
CREATE POLICY select_own_keys ON api_keys
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY insert_own_keys ON api_keys
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY update_own_keys ON api_keys
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY delete_own_keys ON api_keys
  FOR DELETE USING (auth.uid() = user_id);

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_api_keys_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_api_keys_updated_at
  BEFORE UPDATE ON api_keys
  FOR EACH ROW EXECUTE FUNCTION update_api_keys_updated_at();
