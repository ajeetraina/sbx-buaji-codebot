# First stage: build the Go binary
FROM golang:1.23 AS builder

# Set the working directory inside the container
WORKDIR /app

# Copy the Go module files and download dependencies
COPY . ./
RUN go mod tidy

# Build the Go binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o server .

# Second stage: create a minimal image to run the binary
FROM alpine:latest

# Create a non-root user and group
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Set the working directory inside the container
WORKDIR /app

# Copy the binary from the builder stage
COPY --from=builder /app/server .

# Change ownership of the binary to the non-root user
RUN chown appuser:appgroup /app/server

# Switch to the non-root user
USER appuser

# Expose port 6969
EXPOSE 6969

# Command to run the binary
CMD ["./server"]