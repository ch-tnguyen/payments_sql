-- define wash rule
DROP FUNCTION IF EXISTS wash_rule(INTEGER, INTEGER, DATE, DATE);
CREATE FUNCTION wash_rule(year INTEGER, month INTEGER, start_date DATE, end_date DATE)
RETURNS boolean AS $$
DECLARE
	mid_month timestamp;
BEGIN
	mid_month := make_timestamp(year, month, 16, 0, 0, 0); -- all of 15th is included in first half of month
	
	IF start_date < mid_month
	THEN
		IF end_date IS NULL
		THEN
			RETURN TRUE;
		ELSE
			RETURN mid_month <= end_date;
		END IF;
	END IF;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
	month					INTEGER;
	current_month			INTEGER;
	current_year			INTEGER;
	current_person_id		INTEGER;
	cut_off					DATE;
	last_year				DATE;
	
	pm_rec 					hibernate.plan_membership_history%ROWTYPE;
	plan_rec				hibernate.plan%ROWTYPE;
	partner_rec				hibernate.partner%ROWTYPE;
	sponsorship_rec			hibernate.sponsorship%ROWTYPE;
	sponsor_rec				hibernate.sponsor%ROWTYPE;
BEGIN
	current_month := extract(month from current_timestamp);
	current_year := extract(year from current_timestamp);
	last_year := make_date(current_year - 1, 12, 31);

	-- define temporary table
	DROP TABLE IF EXISTS ytd_billing;
	CREATE TABLE ytd_billing (
	    person_id		INTEGER,
	    month			INTEGER,
	    year			INTEGER,
	    count			BOOLEAN,
	    plan_name		VARCHAR(255),
	    partner			VARCHAR(255),
	    sponsor			VARCHAR(255),
	    relationship	VARCHAR(255),
	    tier			INTEGER,
	    cobra			BOOLEAN,
	    CONSTRAINT unique_person_month UNIQUE(person_id, year, month)
	);

	-- go through plan membership history table
	-- for each person
	FOR current_person_id in SELECT DISTINCT hibernate.plan_membership_history.person_id from hibernate.plan_membership_history
	LOOP
		-- for each month in the current year
		month := 1;
		
		LOOP
		    EXIT WHEN month > current_month;
		
			cut_off := make_date(current_year, month + 1, 1);
			
			-- get the last update before the cutoff
			SELECT *
			INTO pm_rec
			FROM hibernate.plan_membership_history as pm
			WHERE pm.person_id = current_person_id
			AND pm.create_timestamp < cut_off
			AND last_year < pm.create_timestamp
			ORDER BY pm.create_timestamp DESC
			LIMIT 1;
			
			SELECT *
			INTO plan_rec
			FROM hibernate.plan as plan
			WHERE pm_rec.plan_id = plan.id;
			
			SELECT *
			INTO partner_rec
			FROM hibernate.partner as partner
			WHERE plan_rec.network_partner_id = partner.id;
			
			SELECT *
			INTO sponsorship_rec
			FROM hibernate.sponsorship as sponsorship
			WHERE pm_rec.person_id = sponsorship.person_id
			AND pm_rec.subscriber_id = sponsorship.subscriber_id;
			
			SELECT sponsor.*
			INTO sponsor_rec
			FROM hibernate.sponsor as sponsor
			WHERE sponsorship_rec.sponsor_id = sponsor.id;
			
			IF pm_rec.create_timestamp IS NOT NULL
			THEN
				INSERT INTO ytd_billing
				("person_id", "year", "month", "count", "plan_name", "partner", "sponsor", "relationship", "tier", "cobra")
				VALUES
				(pm_rec.person_id, current_year, month, wash_rule(current_year, month, pm_rec.start_date, pm_rec.end_date), plan_rec.name, partner_rec.name, sponsor_rec.name, sponsorship_rec.sponsorship_type, -1, pm_rec.is_cobra);
			END IF;
		    
		    month := month + 1;
		END LOOP;
	END LOOP;
END $$;

select * from ytd_billing ORDER BY person_id ASC LIMIT 10;
