import UIKit

final class SessionListViewController: UITableViewController {
    private var sessions: [SavedSessionIndexItem] = []
    var onSelect: ((SavedSession) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Saved Sessions"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reload))
        reload()
    }
    
    @objc private func reload() {
        sessions = SessionManager.shared.listSessions()
        tableView.reloadData()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sessions.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let s = sessions[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = s.name
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        content.secondaryText = formatter.string(from: s.updatedAt)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sessions[indexPath.row]
        if let full = SessionManager.shared.loadSession(id: item.id) {
            onSelect?(full)
        }
        dismiss(animated: true)
    }
}