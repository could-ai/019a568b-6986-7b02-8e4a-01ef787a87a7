-- Supabase Database Schema for FlowChat App
-- This file contains all the necessary SQL statements to set up the database structure
-- Copy and paste this entire content into your Supabase SQL editor and execute it

-- Enable Row Level Security
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Create profiles table (extends Supabase auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  username TEXT UNIQUE,
  full_name TEXT,
  avatar_url TEXT,
  phone_number TEXT,
  bio TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- Create chats table (for conversations - both private and group)
CREATE TABLE IF NOT EXISTS public.chats (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT, -- NULL for private chats, set for groups
  description TEXT,
  avatar_url TEXT,
  is_group BOOLEAN DEFAULT FALSE,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- Create chat_participants table (links users to chats)
CREATE TABLE IF NOT EXISTS public.chat_participants (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'member')), -- for group chats
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  UNIQUE(chat_id, user_id)
);

-- Create messages table
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'video', 'file', 'audio')),
  file_url TEXT, -- for media messages
  reply_to_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
  is_deleted BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- Create message_read_status table (for read receipts)
CREATE TABLE IF NOT EXISTS public.message_read_status (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  read_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  UNIQUE(message_id, user_id)
);

-- Create typing_indicators table (for real-time typing status)
CREATE TABLE IF NOT EXISTS public.typing_indicators (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_typing BOOLEAN DEFAULT FALSE,
  last_updated TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  UNIQUE(chat_id, user_id)
);

-- Enable Row Level Security on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_read_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;

-- Row Level Security Policies

-- Profiles policies
CREATE POLICY "Users can view all profiles" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Chats policies
CREATE POLICY "Users can view chats they participate in" ON public.chats FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.chat_participants WHERE chat_id = chats.id AND user_id = auth.uid())
);
CREATE POLICY "Users can create chats" ON public.chats FOR INSERT WITH CHECK (auth.uid() = created_by);
CREATE POLICY "Chat creators and admins can update chats" ON public.chats FOR UPDATE USING (
  auth.uid() = created_by OR 
  EXISTS (SELECT 1 FROM public.chat_participants WHERE chat_id = chats.id AND user_id = auth.uid() AND role = 'admin')
);

-- Chat participants policies
CREATE POLICY "Users can view participants of chats they are in" ON public.chat_participants FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.chat_participants cp WHERE cp.chat_id = chat_participants.chat_id AND cp.user_id = auth.uid())
);
CREATE POLICY "Users can join chats" ON public.chat_participants FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "Users can leave chats or admins can manage participants" ON public.chat_participants FOR DELETE USING (
  user_id = auth.uid() OR 
  EXISTS (SELECT 1 FROM public.chat_participants cp WHERE cp.chat_id = chat_participants.chat_id AND cp.user_id = auth.uid() AND cp.role = 'admin')
);
CREATE POLICY "Admins can update participant roles" ON public.chat_participants FOR UPDATE USING (
  EXISTS (SELECT 1 FROM public.chat_participants cp WHERE cp.chat_id = chat_participants.chat_id AND cp.user_id = auth.uid() AND cp.role = 'admin')
);

-- Messages policies
CREATE POLICY "Users can view messages in chats they participate in" ON public.messages FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.chat_participants WHERE chat_id = messages.chat_id AND user_id = auth.uid())
);
CREATE POLICY "Users can send messages to chats they participate in" ON public.messages FOR INSERT WITH CHECK (
  sender_id = auth.uid() AND 
  EXISTS (SELECT 1 FROM public.chat_participants WHERE chat_id = messages.chat_id AND user_id = auth.uid())
);
CREATE POLICY "Users can update their own messages" ON public.messages FOR UPDATE USING (sender_id = auth.uid());
CREATE POLICY "Users can delete their own messages" ON public.messages FOR DELETE USING (sender_id = auth.uid());

-- Message read status policies
CREATE POLICY "Users can view read status in their chats" ON public.message_read_status FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.chat_participants WHERE chat_id = (SELECT chat_id FROM public.messages WHERE id = message_read_status.message_id) AND user_id = auth.uid())
);
CREATE POLICY "Users can mark messages as read" ON public.message_read_status FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "Users can update their own read status" ON public.message_read_status FOR UPDATE USING (user_id = auth.uid());

-- Typing indicators policies
CREATE POLICY "Users can view typing status in their chats" ON public.typing_indicators FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.chat_participants WHERE chat_id = typing_indicators.chat_id AND user_id = auth.uid())
);
CREATE POLICY "Users can update their typing status" ON public.typing_indicators FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "Users can update their typing status" ON public.typing_indicators FOR UPDATE USING (user_id = auth.uid());

-- Functions for triggers

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = TIMEZONE('utc'::text, NOW());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers to automatically update updated_at
CREATE TRIGGER handle_updated_at_profiles
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

CREATE TRIGGER handle_updated_at_chats
  BEFORE UPDATE ON public.chats
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

CREATE TRIGGER handle_updated_at_messages
  BEFORE UPDATE ON public.messages
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

CREATE TRIGGER handle_updated_at_typing_indicators
  BEFORE UPDATE ON public.typing_indicators
  FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();

-- Function to create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, username, full_name)
  VALUES (NEW.id, NEW.raw_user_meta_data->>'username', NEW.raw_user_meta_data->>'full_name');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create profile on signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Function to automatically add creator to chat participants
CREATE OR REPLACE FUNCTION public.handle_chat_created()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_group THEN
    INSERT INTO public.chat_participants (chat_id, user_id, role)
    VALUES (NEW.id, NEW.created_by, 'admin');
  ELSE
    INSERT INTO public.chat_participants (chat_id, user_id)
    VALUES (NEW.id, NEW.created_by);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to add creator to chat participants
CREATE TRIGGER on_chat_created
  AFTER INSERT ON public.chats
  FOR EACH ROW EXECUTE PROCEDURE public.handle_chat_created();

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_messages_chat_id_created_at ON public.messages(chat_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON public.messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_chat_id ON public.chat_participants(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON public.chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_message_read_status_message_id ON public.message_read_status(message_id);
CREATE INDEX IF NOT EXISTS idx_typing_indicators_chat_id ON public.typing_indicators(chat_id);

-- Enable realtime for all tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.chats;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.message_read_status;
ALTER PUBLICATION supabase_realtime ADD TABLE public.typing_indicators;