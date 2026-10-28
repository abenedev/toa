"use client";

import { createContext, useContext, useEffect, useState } from "react";
import { API_BASE_URL } from "@/lib/api";

interface User {
	id: number;
	email: string;
	bodyweight?: number;
	is_subscribed?: boolean;
	has_ads?: boolean;
}

interface AuthContextType {
	user: User | null;
	token: string | null;
	login: (email: string, password: string) => Promise<void>;
	signup: (email: string, password: string) => Promise<void>;
	logout: () => void;
	refreshUser: () => Promise<void>;
	isLoading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
	const [user, setUser] = useState<User | null>(null);
	const [token, setToken] = useState<string | null>(null);
	const [isLoading, setIsLoading] = useState(true);

	const fetchUser = async (authToken: string) => {
		try {
			const response = await fetch(`${API_BASE_URL}/auth/me`, {
				headers: {
					Authorization: `Bearer ${authToken}`,
				},
			});

			if (response.ok) {
				const userData = await response.json();
				setUser(userData);
			} else {
				// Token is invalid, clear it
				localStorage.removeItem("token");
				setToken(null);
			}
		} catch (error) {
			console.error("Failed to fetch user:", error);
		} finally {
			setIsLoading(false);
		}
	};

	useEffect(() => {
		// Check for existing token on mount
		const storedToken = localStorage.getItem("token");
		if (storedToken) {
			setToken(storedToken);
			fetchUser(storedToken);
		} else {
			setIsLoading(false);
		}
	}, []);

	const login = async (email: string, password: string) => {
		const response = await fetch(`${API_BASE_URL}/auth/login`, {
			method: "POST",
			headers: {
				"Content-Type": "application/json",
			},
			body: JSON.stringify({ email, password }),
		});

		if (!response.ok) {
			const data = await response.json();
			throw new Error(data.detail || "Login failed");
		}

		const data = await response.json();
		localStorage.setItem("token", data.access_token);
		setToken(data.access_token);
		await fetchUser(data.access_token);
	};

	const signup = async (email: string, password: string) => {
		const response = await fetch(`${API_BASE_URL}/auth/signup`, {
			method: "POST",
			headers: {
				"Content-Type": "application/json",
			},
			body: JSON.stringify({ email, password }),
		});

		if (!response.ok) {
			const data = await response.json();
			throw new Error(data.detail || "Signup failed");
		}

		const data = await response.json();
		localStorage.setItem("token", data.access_token);
		setToken(data.access_token);
		await fetchUser(data.access_token);
	};

	const refreshUser = async () => {
		const storedToken = localStorage.getItem("token");
		if (storedToken) await fetchUser(storedToken);
	};

	const logout = () => {
		localStorage.removeItem("token");
		setToken(null);
		setUser(null);
	};

	return (
		<AuthContext.Provider value={{ user, token, login, signup, logout, refreshUser, isLoading }}>
			{children}
		</AuthContext.Provider>
	);
}

export function useAuth() {
	const context = useContext(AuthContext);
	if (context === undefined) {
		throw new Error("useAuth must be used within an AuthProvider");
	}
	return context;
}