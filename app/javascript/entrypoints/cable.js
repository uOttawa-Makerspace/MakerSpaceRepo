import { createConsumer } from "@rails/actioncable";

// Create the ActionCable consumer instance
const consumer = createConsumer();

// Maintain backwards compatibility with any legacy scripts expecting App.cable
window.App = window.App || {};
window.App.cable = consumer;

// Automatically import and subscribe all channels under channels/
import.meta.glob("../channels/**/*_channel.js", { eager: true });
import.meta.glob("./channels/**/*_channel.js", { eager: true });

export default consumer;
