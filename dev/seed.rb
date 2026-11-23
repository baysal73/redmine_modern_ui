# Demo data for the development instance (fictional, safe to publish).
# Run: bundle exec rails runner plugins/redmine_modern_ui/dev/seed.rb
require 'securerandom'
Setting.rest_api_enabled = '1'
Setting.default_language = 'en'
Setting.host_name = 'localhost:3710'
Setting.protocol = 'http'

pw = 'DemoPassw0rd!2026'
mk = lambda do |login, first, last, lang|
  u = User.find_by_login(login) || User.new(login: login)
  u.firstname = first; u.lastname = last; u.mail = "#{login}@example.org"; u.language = lang
  u.password = pw; u.password_confirmation = pw; u.must_change_passwd = false; u.status = 1
  u.save!; u
end
admin = User.find_by_login('admin'); admin.password = pw; admin.password_confirmation = pw; admin.must_change_passwd = false; admin.save!
alice = mk.('alice', 'Alice', 'Manager', 'en')
bob   = mk.('bob', 'Bob', 'Developer', 'de')
cem   = mk.('cem', 'Cem', 'Reporter', 'tr')
dana  = mk.('dana', 'Dana', 'Viewer', 'en')

mgr = Role.find_by_name('Manager'); dev = Role.find_by_name('Developer'); rep = Role.find_by_name('Reporter')
projects = { 'Website' => 'website', 'Events 2027' => 'events', 'Membership' => 'membership' }.map do |name, ident|
  p = Project.find_by_identifier(ident) || Project.new(name: name, identifier: ident, is_public: false)
  p.enabled_module_names = %w[issue_tracking time_tracking news documents files wiki repository boards calendar gantt]
  p.trackers = Tracker.all
  p.save!; p
end
projects[0].update!(is_public: true)
[[alice, mgr], [bob, dev], [cem, rep]].each { |u, r| projects.each { |p| Member.where(project_id: p.id, user_id: u.id).first_or_create!(roles: [r]) } }
Member.where(project_id: projects[0].id, user_id: dana.id).first_or_create!(roles: [rep]) # dana sees only Website

srand 42
statuses = IssueStatus.all.to_a; prios = IssuePriority.all.to_a; trackers = Tracker.all.to_a
subjects = ['Fix login redirect', 'Update membership form', 'Design new banner', 'Prepare keynote slides',
  'Book venue', 'Translate newsletter', 'Import member list', 'Clean up old pages', 'Add payment option',
  'Check accessibility', 'Write press release', 'Review budget', 'Update FAQ', 'Test mobile layout', 'Archive 2026 files']
users = [alice, bob, cem, nil]
if Issue.count < 10
  60.times do |i|
    p = projects[i % 3]
    author = [alice, bob, cem].sample
    next unless author.member_of?(p)
    issue = Issue.new(project: p, tracker: trackers.sample, author: author, status: statuses.first,
      priority: prios.sample, subject: "#{subjects[i % subjects.size]} ##{i + 1}",
      description: "Demo issue #{i + 1}.\n\nSome *formatted* text with a list:\n\n* one\n* two",
      assigned_to: users.sample, due_date: (Date.today + rand(-5..30)))
    issue.save!
  end
  # spread issues over all statuses (closed ones get a closed_on date)
  Issue.order(:id).each_with_index do |is, n|
    st = statuses[n % statuses.size]
    is.update_columns(status_id: st.id, closed_on: (st.is_closed? ? Time.now : nil))
  end
end
puts "users=#{User.active.count} projects=#{Project.count} issues=#{Issue.count}"
