# System collections

Finished, Reading and To Read are protected collection IDs stored with ordinary collections. Membership uses the existing book collection entries and is changed only by the user. A book may be in any number of collections. Reading progress and imports never change membership.

Schema 23 removes the rejected Phase 1 status table. Status values are not converted to collection memberships. Existing books, collection rows and memberships, progress, annotations and bookmarks are preserved. Initializing the three collections is idempotent and uses internal normalized keys distinct from user display names, including when a user collection is called Reading.
