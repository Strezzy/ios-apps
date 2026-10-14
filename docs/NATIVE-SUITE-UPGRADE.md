# Native suite installation change

Facet, Veil, Lucid and Echo are receiving rebuilt native identities, not just catalog labels. The bundle IDs use com.billy.facet, com.billy.veil, com.billy.lucid and com.billy.echo respectively.

These are new app identities. Keep the previous installation and export any important media or voice recordings before removing it. iOS does not automatically transfer the old app sandbox, preferences or keychain data. Model downloads may need to be installed again. Do not assume that changing a catalog name migrates data.

Older published releases remain available and are not overwritten. The source listing switches each app only after its new IPA passes the native build and packaging checks. Prism and Music are unchanged.

After this one-time identity change, subsequent releases retain the new IDs and can use the normal update process. Physical iPhone testing is still required; simulator results are not physical-device validation.
