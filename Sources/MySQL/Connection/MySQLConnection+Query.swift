import Foundation

extension MySQLConnection {
    public func query(_ string: String, _ parameters: [MySQLDataConvertible]) -> Future<[[MySQLColumn: MySQLData]]> {
        var rows: [[MySQLColumn: MySQLData]] = []
        return self.query(string, parameters) { row in
            rows.append(row)
        }.map(to: [[MySQLColumn: MySQLData]].self) {
            return rows
        }
    }

    public func query(_ string: String, _ parameters: [MySQLDataConvertible],  onRow: @escaping ([MySQLColumn: MySQLData]) throws -> ()) -> Future<Void> {
        let comPrepare = MySQLComStmtPrepare(query: string)
        var ok: MySQLComStmtPrepareOK?
        var columns: [MySQLColumnDefinition41] = []
        return send([.comStmtPrepare(comPrepare)]) { message in
            switch message {
            case .comStmtPrepareOK(let _ok):
                ok = _ok
                return false
            case .columnDefinition41(let col):
                let ok = ok!
                columns.append(col)
                if columns.count == ok.numColumns + ok.numParams {
                    return true
                } else {
                    return false
                }
            case .ok, .eof:
                // ignore ok and eof
                return false
            default: throw MySQLError(identifier: "query", reason: "Unsupported message encountered during prepared query: \(message).", source: .capture())
            }
        }.flatMap(to: Void.self) {
            let ok = ok!
            let comExecute = try MySQLComStmtExecute(
                statementID: ok.statementID,
                flags: 0x00, // which flags?
                values: parameters.map { param in
                    let data = try param.convertToMySQLData()
                    return .init(type: data.type, isUnsigned: false, value: data.value)
                }
            )
            var columns: [MySQLColumnDefinition41] = []
            return self.send([.comStmtExecute(comExecute)]) { message in
                switch message {
                case .columnDefinition41(let col):
                    columns.append(col)
                    return false
                case .binaryResultsetRow(let row):
                    var formatted: [MySQLColumn: MySQLData] = [:]
                    for (i, col) in columns.enumerated() {
                        let data = MySQLData(type: col.columnType, format: .binary, value: row.values[i])
                        formatted[col.makeMySQLColumn()] = data
                    }
                    try onRow(formatted)
                    return false
                case .ok, .eof:
                    // rows are done
                    return true
                default: throw MySQLError(identifier: "query", reason: "Unsupported message encountered during prepared query: \(message).", source: .capture())
                }
            }
        }
    }
}
