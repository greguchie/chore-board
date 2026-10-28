struct HealthStatus: Decodable {
    let status: String
    let dbTime: String // kept as text for now; proper date handling comes in Step 2
}
