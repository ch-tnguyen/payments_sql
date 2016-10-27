DROP FUNCTION IF EXISTS calculate_coverage_tier(subscriber_id INT, plan_id INT);
-- returns [-/E][-/S][-/K/C]
CREATE FUNCTION calculate_coverage_tier(subscriber_id INT, plan_id INT)
RETURNS TEXT AS $$
DECLARE
	self TEXT;
	spouse TEXT;
	children TEXT;
BEGIN
	IF EXISTS ()
	THEN
		SELECT 'E' into self;
	ELSE
		SELECT '-' into self;
	END IF;
	
	SELECT 'S' into spouse;
	SELECT 'K' into children;
	return self || spouse || children;
END;
$$ LANGUAGE plpgsql;

SELECT calculate_coverage_tier(0, 0);