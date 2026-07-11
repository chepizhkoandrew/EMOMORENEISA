ALTER TABLE profiles ADD CONSTRAINT user_pronoun_check CHECK (user_pronoun IS NULL OR user_pronoun IN ('he', 'she', 'they'));
