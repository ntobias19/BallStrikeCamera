def normalize_tee_key(tee_name: str, gender: str = "male") -> str:
    """Normalize tee name to a clean title-cased key for tee_yards_by_tee_box."""
    name = tee_name.strip().title()
    # Strip common suffixes
    for suffix in [" Men", " Women", " Male", " Female"]:
        if name.endswith(suffix):
            name = name[:-len(suffix)].strip()
    return name
