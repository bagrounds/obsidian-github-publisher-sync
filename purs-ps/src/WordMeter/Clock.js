export const nowMsImpl = () => Date.now();

export const formatClockTimeImpl = (timestamp) => {
  const date = new Date(timestamp);
  try {
    return date.toLocaleTimeString([], {
      hour: "numeric",
      minute: "2-digit",
      second: "2-digit",
    });
  } catch (_unused) {
    return date.toISOString().slice(11, 19);
  }
};
