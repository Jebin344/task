using System;
using System.Collections.Generic;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using UnityEngine;

[Serializable]
public class PoseData
{
    public float[][] landmarks;
    public float timestamp;
}

public class PoseReceiver : MonoBehaviour
{
    [Header("Connection")]
    public string serverIP = "127.0.0.1";
    public int serverPort = 8765;

    [Header("Visualization Settings")]
    [Range(0.5f, 5f)]
    public float scaleMultiplier = 2.0f;
    public bool mirrorMode = true;
    [Range(0.1f, 1f)]
    public float smoothing = 0.5f;

    [Header("Visual Style")]
    public Color landmarkColor = Color.green;
    public Color skeletonColor = Color.yellow;
    public Color torsoColor = Color.cyan;
    [Range(0.01f, 0.2f)]
    public float jointSize = 0.05f;
    [Range(0.01f, 0.1f)]
    public float lineThickness = 0.02f;

    [Header("Camera")]
    public Camera targetCamera;

    private TcpClient client;
    private NetworkStream stream;
    private Thread receiveThread;
    private bool isRunning = false;

    private PoseData latestPoseData;
    private readonly object poseLock = new object();

    private Vector3[] smoothedPositions = new Vector3[33];

    private GameObject[] jointSpheres = new GameObject[33];
    private Dictionary<string, LineRenderer> boneLines = new Dictionary<string, LineRenderer>();

    private int[][] connections = new int[][]
    {
        new int[] {0, 1}, new int[] {1, 2}, new int[] {2, 3}, new int[] {3, 7},
        new int[] {0, 4}, new int[] {4, 5}, new int[] {5, 6}, new int[] {6, 8},

        new int[] {9, 10}, new int[] {11, 12},

        new int[] {11, 13}, new int[] {13, 15}, new int[] {15, 17}, new int[] {15, 19}, new int[] {15, 21},
        new int[] {17, 19},

        new int[] {12, 14}, new int[] {14, 16}, new int[] {16, 18}, new int[] {16, 20}, new int[] {16, 22},
        new int[] {18, 20},

        new int[] {11, 23}, new int[] {12, 24}, new int[] {23, 24},

        new int[] {23, 25}, new int[] {25, 27}, new int[] {27, 29}, new int[] {27, 31}, new int[] {29, 31},

        new int[] {24, 26}, new int[] {26, 28}, new int[] {28, 30}, new int[] {28, 32}, new int[] {30, 32}
    };

    void Start()
    {
        if (targetCamera == null)
        {
            targetCamera = Camera.main;
        }

        CreateVisualObjects();
        ConnectToServer();
    }

    void CreateVisualObjects()
    {
        for (int i = 0; i < 33; i++)
        {
            GameObject sphere = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            sphere.name = $"Joint_{i}";
            sphere.transform.parent = transform;
            sphere.transform.localScale = Vector3.one * jointSize;

            Destroy(sphere.GetComponent<Collider>());

            Renderer renderer = sphere.GetComponent<Renderer>();
            renderer.material = new Material(Shader.Find("Standard"));
            renderer.material.color = landmarkColor;

            jointSpheres[i] = sphere;
        }

        int connectionIndex = 0;
        foreach (var connection in connections)
        {
            GameObject lineObj = new GameObject($"Bone_{connectionIndex}");
            lineObj.transform.parent = transform;

            LineRenderer line = lineObj.AddComponent<LineRenderer>();
            line.material = new Material(Shader.Find("Standard"));
            line.startColor = skeletonColor;
            line.endColor = skeletonColor;
            line.startWidth = lineThickness;
            line.endWidth = lineThickness;
            line.positionCount = 2;
            line.useWorldSpace = true;

            boneLines[$"{connection[0]}_{connection[1]}"] = line;
            connectionIndex++;
        }

    }

    void ConnectToServer()
    {
        try
        {
            client = new TcpClient(serverIP, serverPort);
            stream = client.GetStream();
            isRunning = true;

            receiveThread = new Thread(ReceiveData);
            receiveThread.IsBackground = true;
            receiveThread.Start();

            Debug.Log($"Connected to {serverIP}:{serverPort}");
        }
        catch (Exception e)
        {
            Debug.LogError($"Connection failed: {e.Message}");
        }
    }

    void ReceiveData()
    {
        byte[] buffer = new byte[16384];
        StringBuilder messageBuilder = new StringBuilder();

        while (isRunning)
        {
            try
            {
                if (stream != null && stream.DataAvailable)
                {
                    int bytesRead = stream.Read(buffer, 0, buffer.Length);
                    string data = Encoding.UTF8.GetString(buffer, 0, bytesRead);
                    messageBuilder.Append(data);

                    string fullMessage = messageBuilder.ToString();
                    int newlineIndex = fullMessage.IndexOf('\n');

                    while (newlineIndex >= 0)
                    {
                        string message = fullMessage.Substring(0, newlineIndex);
                        ProcessMessage(message);
                        fullMessage = fullMessage.Substring(newlineIndex + 1);
                        newlineIndex = fullMessage.IndexOf('\n');
                    }

                    messageBuilder.Clear();
                    messageBuilder.Append(fullMessage);
                }
                else
                {
                    Thread.Sleep(5);
                }
            }
            catch (Exception e)
            {
            }
        }
    }

    void ProcessMessage(string message)
    {
        try
        {
            PoseData poseData = new PoseData();

            int landmarksStart = message.IndexOf("\"landmarks\": [") + 14;
            int landmarksEnd = message.IndexOf("], \"timestamp\"");

            if (landmarksStart > 14 && landmarksEnd > landmarksStart)
            {
                string landmarksStr = message.Substring(landmarksStart, landmarksEnd - landmarksStart);
                poseData.landmarks = ParseLandmarks(landmarksStr);
            }

            lock (poseLock)
            {
                latestPoseData = poseData;
            }
        }
        catch { }
    }

    float[][] ParseLandmarks(string landmarksStr)
    {
        List<float[]> landmarks = new List<float[]>();
        string[] landmarkStrings = landmarksStr.Split(new string[] { "], [" }, StringSplitOptions.None);

        foreach (string landmarkStr in landmarkStrings)
        {
            string clean = landmarkStr.Replace("[", "").Replace("]", "").Trim();
            string[] values = clean.Split(',');

            if (values.Length >= 3)
            {
                float[] landmark = new float[4];
                float.TryParse(values[0].Trim(), System.Globalization.NumberStyles.Float,
                              System.Globalization.CultureInfo.InvariantCulture, out landmark[0]);
                float.TryParse(values[1].Trim(), System.Globalization.NumberStyles.Float,
                              System.Globalization.CultureInfo.InvariantCulture, out landmark[1]);
                float.TryParse(values[2].Trim(), System.Globalization.NumberStyles.Float,
                              System.Globalization.CultureInfo.InvariantCulture, out landmark[2]);

                if (values.Length >= 4)
                {
                    float.TryParse(values[3].Trim(), System.Globalization.NumberStyles.Float,
                                  System.Globalization.CultureInfo.InvariantCulture, out landmark[3]);
                }

                landmarks.Add(landmark);
            }
        }

        return landmarks.ToArray();
    }

    void Update()
    {

        if (latestPoseData == null || latestPoseData.landmarks == null || latestPoseData.landmarks.Length < 33)
        {
            return;
        }

        lock (poseLock)
        {
            UpdateVisualization();
        }
    }

    void UpdateVisualization()
    {
        for (int i = 0; i < 33; i++)
        {
            Vector3 targetPos = GetLandmarkPosition(i);
            smoothedPositions[i] = Vector3.Lerp(smoothedPositions[i], targetPos, smoothing);
        }

        for (int i = 0; i < 33; i++)
        {
            if (jointSpheres[i] != null)
            {
                jointSpheres[i].transform.position = transform.position + smoothedPositions[i];

                Renderer renderer = jointSpheres[i].GetComponent<Renderer>();
                if (i >= 11 && i <= 22)
                {
                    renderer.material.color = Color.Lerp(landmarkColor, Color.red, 0.3f);
                }
                else if (i >= 23 && i <= 32)
                {
                    renderer.material.color = Color.Lerp(landmarkColor, Color.blue, 0.3f);
                }
                else
                {
                    renderer.material.color = Color.Lerp(landmarkColor, Color.yellow, 0.3f);
                }
            }
        }

        foreach (var connection in connections)
        {
            int from = connection[0];
            int to = connection[1];
            string key = $"{from}_{to}";

            if (boneLines.ContainsKey(key))
            {
                LineRenderer line = boneLines[key];
                line.SetPosition(0, transform.position + smoothedPositions[from]);
                line.SetPosition(1, transform.position + smoothedPositions[to]);

                if ((from >= 23 && from <= 24) || (to >= 23 && to <= 24))
                {
                    line.startColor = torsoColor;
                    line.endColor = torsoColor;
                }
                else
                {
                    line.startColor = skeletonColor;
                    line.endColor = skeletonColor;
                }
            }
        }
    }

    Vector3 GetLandmarkPosition(int index)
    {
        if (latestPoseData == null || latestPoseData.landmarks == null ||
            index >= latestPoseData.landmarks.Length)
            return Vector3.zero;

        var lm = latestPoseData.landmarks[index];
        if (lm == null || lm.Length < 3) return Vector3.zero;

        float x = (lm[0] - 0.5f) * scaleMultiplier;
        float y = (0.5f - lm[1]) * scaleMultiplier;
        float z = -lm[2] * scaleMultiplier;

        if (mirrorMode)
        {
            x = -x;
        }

        return new Vector3(x, y, z);
    }

    void OnApplicationQuit()
    {
        Disconnect();
    }

    void OnDestroy()
    {
        Disconnect();

        foreach (var sphere in jointSpheres)
        {
            if (sphere != null) Destroy(sphere);
        }

        foreach (var line in boneLines.Values)
        {
            if (line != null) Destroy(line.gameObject);
        }
    }

    void Disconnect()
    {
        isRunning = false;

        if (receiveThread != null && receiveThread.IsAlive)
        {
            receiveThread.Join(1000);
        }

        if (stream != null) stream.Close();
        if (client != null) client.Close();

        Debug.Log("Disconnected from server");
    }
}