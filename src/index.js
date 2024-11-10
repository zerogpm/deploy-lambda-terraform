// src/index.js
import { S3Client, ListBucketsCommand } from "@aws-sdk/client-s3";

const s3Client = new S3Client({ 
    region: process.env.CUSTOM_AWS_REGION || 'us-east-1'
});

export const handler = async (event, context) => {
    try {
        const command = new ListBucketsCommand({});
        const response = await s3Client.send(command);

        const buckets = response.Buckets.map(bucket => ({
            name: bucket.Name,
            creationDate: bucket.CreationDate
        }));

        // Return response without stringifying the body
        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json'
            },
            body: {  // Remove JSON.stringify here.
                buckets: buckets,
                count: buckets.length
            }
        };

    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            body: {  // Remove JSON.stringify here
                error: error.message
            }
        };
    }
};