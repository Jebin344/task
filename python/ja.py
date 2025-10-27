import cv2
import mediapipe as mp
import socket
import json
import threading
import numpy as np
from collections import deque
import time

class PoseTCPServer:
    def __init__(self, host='0.0.0.0', port=8765):
        self.host = host
        self.port = port
        self.server_socket = None
        self.clients = []
        self.running = False
        
        self.mp_pose = mp.solutions.pose
        self.pose = self.mp_pose.Pose(
            static_image_mode=False,
            model_complexity=1,
            smooth_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        )
        self.mp_drawing = mp.solutions.drawing_utils
        
        self.smoothing_window = 3
        self.landmark_buffer = deque(maxlen=self.smoothing_window)
        
        self.clients_lock = threading.Lock()
        
        self.frame_count = 0
        self.start_time = time.time()
    
    def smooth_landmarks(self, landmarks):
        """Apply smoothing to reduce jitter"""
        self.landmark_buffer.append(landmarks)
        
        if len(self.landmark_buffer) < 2:
            return landmarks
        
        smoothed = np.mean(self.landmark_buffer, axis=0)
        return smoothed
    
    def process_frame(self, frame):
        """Process frame and extract pose data"""
        frame = cv2.flip(frame, 1)
        
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = self.pose.process(rgb_frame)
        
        if results.pose_landmarks:
            landmarks = []
            for landmark in results.pose_landmarks.landmark:
                landmarks.append([
                    float(landmark.x),
                    float(landmark.y),
                    float(landmark.z),
                    float(landmark.visibility)
                ])
            
            landmarks_array = np.array(landmarks)
            smoothed_landmarks = self.smooth_landmarks(landmarks_array)
            
            self.mp_drawing.draw_landmarks(
                frame,
                results.pose_landmarks,
                self.mp_pose.POSE_CONNECTIONS,
                self.mp_drawing.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=2),
                self.mp_drawing.DrawingSpec(color=(0, 0, 255), thickness=2)
            )
            
            # # Add FPS counter
            # self.frame_count += 1
            # elapsed = time.time() - self.start_time
            # if elapsed > 0:
            #     fps = self.frame_count / elapsed
            #     cv2.putText(frame, f'FPS: {fps:.1f}', (10, 30), 
            #                cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
            
            # # Add client count
            # with self.clients_lock:
            #     cv2.putText(frame, f'Clients: {len(self.clients)}', (10, 70), 
            #                cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
            
            pose_data = {
                'landmarks': smoothed_landmarks.tolist(),
                'timestamp': time.time()
            }
            
            return pose_data, frame
        
        return None, frame
    
    def handle_client(self, client_socket, address):
        """Handle individual client connection"""
        print(f"✓ Client connected: {address}")
        
        with self.clients_lock:
            self.clients.append(client_socket)
        
        try:
            while self.running:
                time.sleep(0.1)
        except Exception as e:
            print(f"Error with client {address}: {e}")
        finally:
            with self.clients_lock:
                if client_socket in self.clients:
                    self.clients.remove(client_socket)
            try:
                client_socket.close()
            except:
                pass
            print(f"✗ Client disconnected: {address}")
    
    def broadcast_pose_data(self, pose_data):
        """Broadcast pose data to all clients"""
        if not pose_data:
            return
        
        try:
            message = json.dumps(pose_data) + '\n'
            message_bytes = message.encode('utf-8')
            
            with self.clients_lock:
                disconnected = []
                for client in self.clients:
                    try:
                        client.sendall(message_bytes)
                    except Exception as e:
                        disconnected.append(client)
                
                for client in disconnected:
                    if client in self.clients:
                        self.clients.remove(client)
                    try:
                        client.close()
                    except:
                        pass
        except Exception as e:
            print(f"Broadcast error: {e}")
    
    def accept_connections(self):
        """Accept incoming client connections"""
        
        while self.running:
            try:
                self.server_socket.settimeout(1.0)
                client_socket, address = self.server_socket.accept()
                client_thread = threading.Thread(
                    target=self.handle_client,
                    args=(client_socket, address),
                    daemon=True
                )
                client_thread.start()
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"Error accepting connection: {e}")
    
    def capture_and_process(self):
        """Capture webcam and process poses"""
        cap = cv2.VideoCapture(0)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        cap.set(cv2.CAP_PROP_FPS, 30)
        
        if not cap.isOpened():
            return
        
        print("Press 'q' to quit")
        print("-" * 50)
        
        while self.running and cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break
            
            pose_data, processed_frame = self.process_frame(frame)
            
            if pose_data:
                self.broadcast_pose_data(pose_data)
            
            cv2.imshow('MediaPipe Pose Tracking Server', processed_frame)
            
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                print("\n⏹ Stopping server...")
                self.running = False
                break
            elif key == ord('r'):
                self.frame_count = 0
                self.start_time = time.time()
        
        cap.release()
        cv2.destroyAllWindows()
        print("📹 Webcam released")
    
    def start(self):
        """Start the TCP server"""
        self.running = True
        
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind((self.host, self.port))
            self.server_socket.listen(5)
        
            
            accept_thread = threading.Thread(target=self.accept_connections, daemon=True)
            accept_thread.start()
            
            self.capture_and_process()
            
        except Exception as e:
            print(f"❌ Server error: {e}")
        finally:
            self.running = False
            
            if self.server_socket:
                self.server_socket.close()
            
            with self.clients_lock:
                for client in self.clients:
                    try:
                        client.close()
                    except:
                        pass
            
            print("=" * 50)
            print("✓ Server stopped")
            print("=" * 50)

if __name__ == "__main__":
    print("\n" + "=" * 50)
    print("  MediaPipe Pose Tracking - TCP Server")
    print("=" * 50)
    print("\nStarting server...")
    
    server = PoseTCPServer(host='0.0.0.0', port=8765)
    
    try:
        server.start()
    except KeyboardInterrupt:
        print("\n\n⚠ Interrupted by user")
        server.running = False
    except Exception as e:
        print(f"\n❌ Fatal error: {e}")