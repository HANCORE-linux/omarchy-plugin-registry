# The namespace behind a plugin. `claimed` false means the listing was seeded
# from the legacy marketplace and no author has proven control of the source
# repo yet — a native browser should say so rather than imply endorsement.
json.name publisher.name
json.display_name publisher.display_name.presence || publisher.name
json.kind publisher.kind
json.bio publisher.bio
json.website publisher.website
json.claimed publisher.claimed?
json.verified publisher.verified?
json.url absolute_url(publisher_path(publisher.name))
