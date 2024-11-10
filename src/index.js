// src/index.js
import { S3Client, ListBucketsCommand } from "@aws-sdk/client-s3";

const s3Client = new S3Client({ region: process.env.AWS_REGION });

export const handler = async (event, context) => {
    try {
        const command = new ListBucketsCommand({});
        const response = await s3Client.send(command);

        const buckets = response.Buckets.map(bucket => ({
            name: bucket.Name,
            creationDate: bucket.CreationDate
        }));

        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                buckets: buckets,
                count: buckets.length
            }, null, 2)
        };

    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({
                error: error.message
            })
        };
    }
};