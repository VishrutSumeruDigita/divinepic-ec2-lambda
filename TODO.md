## Approach to making a lambda function



# Stage 1 -> API endpoint for bulk upload sanity , ensure that the bulk endpoint can do process in background without breaking the production


# Stage 2 -> Configuring the lambda handler and getting the nesecarry perms to create an GPU instance for image embedding


# Stage 3 -> Choice of stack


+---------------------+
|  Lambda Function    |
| (Trigger on Invoke) |
+---------------------+
           |
           v
+-------------------------------+
|     EC2 GPU Instance          |
|  (Starts when triggered)      |
|                               |
|  +-------------------------+  |
|  |  Docker Container       |  |
|  |  (FastAPI App)          |  |
|  +-------------------------+  |
|           |       |           |
|           |       v           |
|           |   +------------+  |
|           |   | S3 Bucket  |  |
|           |   | (Images)   |  |
|           |   +------------+  |
|           |                   |
|           v                   |
|  +------------------------+   |
|  | Elasticsearch (Remote) |   |
|  | (Vector Storage)       |   |
|  +------------------------+   |
+-------------------------------+




