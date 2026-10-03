struct MethodDescriptor: Equatable {
    let name: String
    let startLine: Int
    let endLine: Int
    let complexity: Int
    let enclosingType: String?
}
