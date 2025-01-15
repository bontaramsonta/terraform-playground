// index.js
exports.handler = async (event) => {
  console.log("Received event:", JSON.stringify(event, null, 2));
  console.log("Parsed body:", event.body);
  return {
    statusCode: 200,
    body: JSON.stringify({ message: "Event logged successfully" }),
  };
};
