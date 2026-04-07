#!/usr/bin/env python3
"""
Simulate multiple users wandering around within 10 miles of a center point.
They register, create/join a group, and send location updates via WebSocket.
"""

import asyncio
import json
import math
import random
import time
import requests
import websockets

BASE = "http://100.71.94.116:8080"
WS_BASE = "ws://100.71.94.116:8080/ws"

# Center: Maryland Heights, Missouri
CENTER_LAT = 38.7131
CENTER_LON = -90.4268

# 10 mile radius in degrees (rough)
RADIUS_DEG = 10 / 69.0  # ~0.145 degrees

FAKE_USERS = [
    {"username": "sarah", "display_name": "Sarah"},
    {"username": "mom", "display_name": "Mom"},
    {"username": "dad", "display_name": "Dad"},
    {"username": "jake", "display_name": "Jake"},
]

def register_or_login(username, display_name, password="fakepass123"):
    """Register a user, or login if already exists."""
    r = requests.post(f"{BASE}/api/register", json={
        "username": username,
        "display_name": display_name,
        "password": password,
    })
    if r.status_code == 200:
        print(f"  Registered {username}")
        return r.json()["token"]
    elif r.status_code == 409:
        # Already exists, login
        r = requests.post(f"{BASE}/api/login", json={
            "username": username,
            "password": password,
        })
        if r.status_code == 200:
            print(f"  Logged in {username}")
            return r.json()["token"]
    print(f"  Failed for {username}: {r.status_code} {r.text}")
    return None

def create_group(token, name):
    """Create a group and return its ID."""
    r = requests.post(f"{BASE}/api/groups", json={"name": name},
                      headers={"Authorization": f"Bearer {token}"})
    if r.status_code == 200:
        return r.json()["id"]
    return None

def add_member(token, group_id, user_id):
    """Add a member to a group."""
    r = requests.post(f"{BASE}/api/groups/{group_id}/members",
                      json={"user_id": user_id},
                      headers={"Authorization": f"Bearer {token}"})
    return r.status_code == 200

def send_share_request(token, to_user_id):
    """Send a share request."""
    r = requests.post(f"{BASE}/api/shares/request",
                      json={"to_user_id": to_user_id},
                      headers={"Authorization": f"Bearer {token}"})
    return r.json().get("id") if r.status_code == 200 else None

def accept_share_request(token, request_id):
    """Accept a share request."""
    r = requests.post(f"{BASE}/api/shares/requests/{request_id}/accept",
                      headers={"Authorization": f"Bearer {token}"})
    return r.status_code == 200

def get_incoming_requests(token):
    """Get incoming share requests."""
    r = requests.get(f"{BASE}/api/shares/requests",
                     headers={"Authorization": f"Bearer {token}"})
    return r.json() if r.status_code == 200 else []


class FakeUser:
    def __init__(self, username, display_name, token, group_id):
        self.username = username
        self.display_name = display_name
        self.token = token
        self.group_id = group_id
        self.user_id = f"{username}@point.local"

        # Start at a random position within radius
        angle = random.uniform(0, 2 * math.pi)
        dist = random.uniform(0.3, 1.0) * RADIUS_DEG
        self.lat = CENTER_LAT + dist * math.sin(angle)
        self.lon = CENTER_LON + dist * math.cos(angle)

        # Random heading and speed
        self.heading = random.uniform(0, 360)
        self.speed_mps = random.uniform(8, 25)  # 18-56 mph (driving speed)
        self.battery = random.randint(20, 100)

    def update_position(self, dt):
        """Move in the current direction, occasionally turning."""
        # Occasionally change heading
        if random.random() < 0.15:
            self.heading += random.uniform(-60, 60)

        # Occasionally change speed
        if random.random() < 0.1:
            self.speed_mps = random.uniform(5, 30)

        # Sometimes stop briefly
        if random.random() < 0.03:
            self.speed_mps = 0
        elif self.speed_mps == 0 and random.random() < 0.3:
            self.speed_mps = random.uniform(8, 25)

        # Move
        heading_rad = math.radians(self.heading)
        # Convert speed (m/s) to degrees per second
        speed_deg = self.speed_mps / 111000  # rough m to degrees

        self.lat += speed_deg * math.cos(heading_rad) * dt
        self.lon += speed_deg * math.sin(heading_rad) * dt

        # Bounce off radius boundary
        dist_from_center = math.sqrt((self.lat - CENTER_LAT)**2 + (self.lon - CENTER_LON)**2)
        if dist_from_center > RADIUS_DEG:
            # Turn back toward center
            self.heading = math.degrees(math.atan2(
                CENTER_LON - self.lon, CENTER_LAT - self.lat
            )) + random.uniform(-30, 30)

        # Battery drain
        if random.random() < 0.02:
            self.battery = max(5, self.battery - 1)


async def run_fake_user(user: FakeUser):
    """Connect via WebSocket and send location updates."""
    uri = f"{WS_BASE}?token={user.token}"

    while True:
        try:
            async with websockets.connect(uri) as ws:
                print(f"  [{user.username}] Connected to WebSocket")

                # Send presence
                await ws.send(json.dumps({
                    "type": "presence.update",
                    "battery": user.battery,
                    "activity": "driving" if user.speed_mps > 5 else "stationary",
                }))

                while True:
                    # Update position
                    user.update_position(10)  # 10 second steps

                    import base64
                    location_data = {
                        "lat": round(user.lat, 6),
                        "lon": round(user.lon, 6),
                        "accuracy": random.uniform(5, 20),
                        "speed": user.speed_mps,
                        "heading": user.heading,
                        "battery": user.battery,
                        "activity": "driving" if user.speed_mps > 5 else "stationary",
                        "timestamp": int(time.time()),
                    }
                    blob = base64.b64encode(json.dumps(location_data).encode()).decode()

                    # Send to group
                    msg = {
                        "type": "location.update",
                        "recipient_type": "group",
                        "recipient_id": user.group_id,
                        "encrypted_blob": blob,
                        "source_type": "gps",
                        "timestamp": int(time.time()),
                        "ttl": 300,
                    }
                    await ws.send(json.dumps(msg))

                    # Drain incoming messages (don't block)
                    try:
                        while True:
                            await asyncio.wait_for(ws.recv(), timeout=0.1)
                    except (asyncio.TimeoutError, websockets.exceptions.ConnectionClosed):
                        pass

                    # Wait 10 seconds between updates
                    await asyncio.sleep(10)

        except Exception as e:
            print(f"  [{user.username}] Disconnected: {e}, reconnecting in 5s...")
            await asyncio.sleep(5)


async def main():
    print("=== Setting up fake users ===")

    # Register all fake users
    tokens = {}
    for u in FAKE_USERS:
        token = register_or_login(u["username"], u["display_name"])
        if token:
            tokens[u["username"]] = token

    if not tokens:
        print("No users registered, exiting")
        return

    # First fake user creates the group
    first_user = FAKE_USERS[0]["username"]
    first_token = tokens[first_user]

    print("\n=== Creating group ===")
    group_id = create_group(first_token, "Demo Family")
    if not group_id:
        print("Failed to create group")
        return
    print(f"  Group ID: {group_id}")

    # Add all other fake users to the group
    for u in FAKE_USERS[1:]:
        if u["username"] in tokens:
            user_id = f"{u['username']}@point.local"
            if add_member(first_token, group_id, user_id):
                print(f"  Added {u['username']} to group")

    # Register parker if not already
    parker_token = register_or_login("parker", "Parker")
    if parker_token:
        tokens["parker"] = parker_token
        # Add parker to the group
        if add_member(first_token, group_id, "parker@point.local"):
            print(f"  Added parker to group")

        # Also set up 1:1 shares between fake users and parker
        print("\n=== Setting up 1:1 shares ===")
        for u in FAKE_USERS:
            if u["username"] in tokens:
                req_id = send_share_request(tokens[u["username"]], "parker@point.local")
                if req_id:
                    print(f"  {u['username']} sent share request to parker")

        # Accept all incoming requests for parker
        incoming = get_incoming_requests(parker_token)
        for req in incoming:
            if accept_share_request(parker_token, req["id"]):
                print(f"  Parker accepted request from {req['from_user_id']}")

    # Create fake user objects
    print("\n=== Starting simulation ===")
    print(f"  Center: {CENTER_LAT}, {CENTER_LON}")
    print(f"  Radius: ~10 miles")
    print(f"  Users: {', '.join(tokens.keys())}")
    print(f"  Update interval: 10 seconds")
    print(f"  Press Ctrl+C to stop\n")

    fake_users = []
    for u in FAKE_USERS:
        if u["username"] in tokens:
            fake_users.append(FakeUser(
                u["username"], u["display_name"],
                tokens[u["username"]], group_id
            ))

    # Run all fake users concurrently
    tasks = [asyncio.create_task(run_fake_user(u)) for u in fake_users]

    # Print positions periodically
    while True:
        await asyncio.sleep(30)
        print(f"\n  --- Positions at {time.strftime('%H:%M:%S')} ---")
        for u in fake_users:
            speed_mph = u.speed_mps * 2.237
            print(f"  {u.username:8s}  {u.lat:.4f}, {u.lon:.4f}  {speed_mph:.0f}mph  🔋{u.battery}%")


if __name__ == "__main__":
    asyncio.run(main())
